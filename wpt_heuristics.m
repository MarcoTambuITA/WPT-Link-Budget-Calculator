function h = wpt_heuristics(freq_Hz)
% WPT_HEURISTICS  Frequency-dependent smart defaults for realistic mode.
%
% Returns physically motivated "educated guess" parameters based on the
% operating frequency. Calibrated to HSMS-2850 Schottky diode data and
% typical SMA/PCB connector losses.
%
% Usage:
%   h = wpt_heuristics(2.45e9);
%   fprintf('n = %.2f, L_hw = %.1f dB, eta_peak = %.1f%%\n', ...
%       h.n_path, h.L_hardware_dB, h.eta_peak * 100);
%
% OUTPUTS (struct):
%   n_path        - Path loss exponent (2.0 at 10 MHz -> ~2.4 at 5.8 GHz)
%   L_hardware_dB - Hardware/insertion loss (2.0 -> ~3.4 dB)
%   eta_max       - Maximum rectenna efficiency at low frequency (0.65)
%   f_rolloff     - Junction capacitance rolloff frequency (5 GHz)
%   eta_peak      - Peak rectenna efficiency at this frequency
%   P_thresh      - Sigmoid midpoint: P_rx (dBm) for 50% of eta_peak
%   P_slope       - Sigmoid steepness (dBm per e-fold)

    % ---- Path Loss Exponent ----
    % Higher frequencies suffer more scattering and alignment losses.
    % Log-linear scaling: 2.0 at 10 MHz, ~2.4 at 5.8 GHz.
    h.n_path = 2.0 + 0.15 * log10(freq_Hz / 10e6);
    h.n_path = max(min(h.n_path, 3.0), 2.0);

    % ---- Hardware / Insertion Loss ----
    % Connector, cable, and trace losses scale with frequency.
    % 2.0 dB at low freq, ~3.4 dB at 5.8 GHz. Capped at 4.0 dB.
    h.L_hardware_dB = 2.0 + 0.5 * log10(freq_Hz / 10e6);
    h.L_hardware_dB = max(min(h.L_hardware_dB, 4.0), 1.0);

    % ---- Rectenna: HSMS-2850 Schottky Diode Model ----
    % Two-factor model: frequency rolloff x power sensitivity.
    %
    % Factor 1: Empirical matching-network and PCB parasitic rolloff.
    %   The intrinsic C_j cutoff of the HSMS-2850 is ~161 GHz, far above
    %   our operating range. The 5 GHz rolloff here captures the practical
    %   bandwidth limitation of typical rectenna matching networks, PCB
    %   trace parasitics, and harmonic termination losses.
    %   eta_peak(f) = eta_max / (1 + (f / f_rolloff)^2)
    h.eta_max   = 0.65;        % Peak efficiency at DC/low frequency
    h.f_rolloff = 5e9;         % -3 dB rolloff frequency (empirical, not C_j)
    h.eta_peak  = h.eta_max / (1 + (freq_Hz / h.f_rolloff)^2);

    % Factor 2: Power sensitivity (sigmoid turn-on)
    %   eta(P_rx) = eta_peak * sigmoid((P_rx - P_thresh) / P_slope)
    %   Below P_thresh: diode barely conducts -> eta ~ 0
    %   Above P_thresh: eta plateaus at eta_peak
    h.P_thresh = -20;          % dBm, 50% turn-on point
    h.P_slope  = 8;            % dBm, soft turn-on (zero-bias Schottky)
end
