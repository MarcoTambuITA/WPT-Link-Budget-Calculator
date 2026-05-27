clear;
clc;
close all;

% --- INPUTS ---
P_tx_dBm = 20;       % Transmit power in dBm
G_tx_dBi = 6;        % Transmit antenna gain in dBi
G_rx_dBi = 6;        % Receive antenna gain in dBi
freq_GHz = 2.45;     % Frequency in GHz
n_path = 2;          % Path loss exponent (2 = free space)
eff_rectenna = 0.60; % Rectenna efficiency (60% written as a decimal)
D_antenna_m = 0.05;  % Largest dimension of antenna in meters (5 cm)

% --- CONSTANTS & SETUP ---
c = 3e8; % Speed of light in m/s
P_tx_W = 10^((P_tx_dBm - 30) / 10); % Convert TX power to Watts once
d_meters = linspace(0.1, 5, 500);   % Create 500 distance points

% --- THE FREQUENCY SWEEP ---
% We define an array of the frequencies you want to compare
freqs_to_test_GHz = [0.915, 2.45, 5.0]; 
colors = ['r', 'g', 'b']; % Assigning red, green, and blue to the curves

figure('Color', 'w');
hold on; grid on;

% This loop will run 3 times (once for each frequency)
for i = 1:length(freqs_to_test_GHz)
    
    % 1. Current Wavelength
    freq_Hz = freqs_to_test_GHz(i) * 1e9;
    lambda = c / freq_Hz;
    
    % 2. Path Loss Array
    path_loss_dB = 20 * log10(4 * pi / lambda) + 10 * n_path * log10(d_meters);
    
    % 3. RF & DC Power Arrays
    P_rx_dBm = P_tx_dBm + G_tx_dBi + G_rx_dBi - path_loss_dB;
    P_rx_W = 10.^((P_rx_dBm - 30) ./ 10);
    P_dc_W = P_rx_W .* eff_rectenna;
    
    % 4. System Efficiency Array
    eff_system_pct = (P_dc_W ./ P_tx_W) .* 100;
    
    % 5. Plot this specific frequency's curve
    plot(d_meters, eff_system_pct, 'LineWidth', 2, 'Color', colors(i), ...
         'DisplayName', sprintf('%.3f GHz', freqs_to_test_GHz(i)));
end

% --- PLOT FORMATTING ---
xlabel('Distance (meters)');
ylabel('System Efficiency (%)');
title('Far-Field WPT: Frequency Comparison');
legend('show'); % Turns on the legend using the DisplayNames from the loop
xlim([0.1 5]);