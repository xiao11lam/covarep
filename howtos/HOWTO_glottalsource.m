% Short test script for running algorithms related to the glottal source
%
% Please find the path management in the startup.m script in the root directory
% of this repository. Note that by starting matlab in the root directory, this
% script should automatically run. If it is not the case, you can also move to the
% root directory and run this script manually. 
%
% License
%  This file is under the LGPL license,  you can
%  redistribute it and/or modify it under the terms of the GNU Lesser General 
%  Public License as published by the Free Software Foundation, either version 3 
%  of the License, or (at your option) any later version. This file is
%  distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
%  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
%  PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
%  details.
%
% This function is part of the Covarep project: http://covarep.github.io/covarep
%

clear all;

% Settings
F0min = 80; % Minimum F0 set to 80 Hz
F0max = 500; % Maximum F0 set to 80 Hz
frame_shift = 10; % Frame shift in ms

% Load soundfile
[x,fs] = audioread(['howtos' filesep 'arctic_a0007.wav']);

% Check the speech signal polarity
polarity = polarity_reskew(x,fs);
x=polarity*x;

% Extract the pitch and voicing information
[srh_f0,srh_vuv,srh_vuvc,srh_time] = pitch_srh(x,fs,F0min,F0max,frame_shift);

% Extract the maximum voiced frequency
[max_voiced_freq] = maximum_voiced_frequency(x,fs,srh_f0.*srh_vuv,srh_time);

% Creaky probability estimation
warning off
try
    [creak_pp,creak_bin] = detect_creaky_voice(x,fs); % Detect creaky voice
    creak=interp1(creak_bin(:,2),creak_bin(:,1),1:length(x));
    creak(creak<0.5)=0; creak(creak>=0.5)=1;
    do_creak=1;
catch
    disp('Version or toolboxes do not support neural network object used in creaky voice detection. Creaky detection skipped.')
    creak=zeros(length(x),1);
    creak_pp=zeros(length(x),2);
    creak_pp(:,2)=1:length(x);
    do_creak=0;
end
warning on

% GCI estimation  （Glottal Closure Instant）一般是第一步 GCIs refer to the moments of most significant excitation that occur at the level of the vocal folds during each glottal.
% 这里GCI主要可以用来分析glottal信号，并且说creaky声音有一些glottal的cue可以识别，所以借由glottal声音的分析我们能够较为容易地识别creaky声音。
% 有两种GCI信号一种叫DEGG就是electroglottographic signal信号，还有一种是LP-residual信号。DEGG是EGG的导数通过laryngograph仪器。
period (Smits and Yegnanarayana, 1995)
sd_gci = gci_sedreams(x,fs,median(srh_f0),1);        % SEDREAMS
% SE-VQ 在这里是一个升级版的来优化现在的GCI传统算法，
se_gci = se_vq(x,fs,median(srh_f0),creak);           % SE-VQ （SEDREAMS algorithm (SE) modified to better handle voice qualities (-VQ) ）

%res = lpcresidual(x,25/1000*fs,5/1000*fs,fs/1000+2); % LP residual
res = maxlpresidual(x,fs,round(fs/1000)+2);

m = mdq(res,fs,se_gci); % Maxima dispersion quotient measurement

ps = peakslope(x,fs);   % peakSlope extraction

[gf_iaif,gfd_iaif] = iaif_ola(x,fs);    % Glottal flow (and derivative) by the IAIF method

dgf_cc = complex_cepstrum(x,fs,sd_gci,srh_f0,srh_vuv); % Glottal flow derivative by the complex cesptrum-based method

[NAQ,QOQ,H1H2,HRF,PSP] = get_vq_params(gf_iaif,gfd_iaif,fs,se_gci); % Estimate conventional glottal parameters

% Estimate the Rd parameter of the Liljencrants-Fant (LF) model
srh_f0(find(srh_f0==0)) = 100;
opt = sin_analysis();
opt.fharmonic  = true;
opt.use_ls     = false;
opt.debug = 0;
frames = sin_analysis(x, fs, [srh_time(:),srh_f0(:)], opt);
rds = rd_msp(frames, fs);

% Extract Cepstral Peak Prominence 
CPPv = cpp( x, fs, 1, 'mean' );

% Plots
t=(0:length(x)-1)/fs;

fig(1) = subplot(311);
    plot(t,x, 'b');
    hold on
    plot(srh_time, srh_vuv, 'g');
    % 这里展示了两种不同的gci算法。对比本文的se_gci。
    stem(sd_gci,ones(1,length(sd_gci))*-.1,'m');
    stem(se_gci,ones(1,length(se_gci))*-.1,'r');
    legend('Speech signal','Voicing (SRH)', 'GCI (SEDREAMS)','GCI (SE-VQ)');
    xlabel('Time [s]');
    ylabel('Amplitude');

fig(2) = subplot(312);
    plot(srh_time, srh_f0, 'r');
    legend('f0 (SRH)');
    xlabel('Time [s]');
    ylabel('Hz');
    
fig(3) = subplot(313);
    % 这里是那个频段的f0追踪
    plot(srh_time, max_voiced_freq, 'g');
    legend('Maximum voiced frequency');
    xlabel('Time [s]');
    ylabel('Hz');

linkaxes(fig, 'x');
xlim([0 srh_time(end)]);
figure
    
fig(4) = subplot(311);
    plot(t,x, 'b');
    hold on
    plot(ps(:,1), ps(:,2),'--b');
    plot(m(:,1),m(:,2),'m');
    plot(rds(:,1), rds(:,2), 'r');
    %  Maxima Dispersion Quotient 可以用来区分breathy 气声类似叹气 to tense声音者紧张的声音。MDQ用到了SE-VQ算法来先得到GCIs。
    legend('Speech signal','PeakSlope','MDQ','Rd');
    xlabel('Time [s]');

fig(5) = subplot(312);
    plot(t,x, 'b');
    hold on
    plot(t,norm(x)*gf_iaif./norm(gf_iaif), 'g');
    plot(creak_pp(:,2)/fs,creak_pp(:,1),'r')
    xlabel('Time [s]');
    ylabel('Amplitude');
    legend('Speech signal','Glottal flow (IAIF)','Creaky voice probability','Location','NorthWest');
    
fig(6) = subplot(313);
    plot(t,x, 'b');
    hold on
    plot(t,norm(x)*dgf_cc./norm(dgf_cc), 'r');    
    xlabel('Time [s]');
    ylabel('Amplitude');
    legend('Speech signal','Glottal flow derivative (CC)');

linkaxes(fig, 'x');
xlim([0 srh_time(end)]);
