function curve = load_rectenna_curve(filepath)
% LOAD_RECTENNA_CURVE  Parse an LTspice CSV into [P_rx_dBm, efficiency].
%
% Expected format: 2-column CSV where Column 1 = input power (dBm),
% Column 2 = DC conversion efficiency as a decimal (0 to 1).
%
% Extrapolation policy (enforced by wpt_farfield_model):
%   - Below min P_rx in table -> eff = 0 (diode fails to turn on)
%   - Above max P_rx in table -> eff = max in table (flatline)
%
% Usage:
%   curve = load_rectenna_curve('hsms2850_efficiency.csv');
%   params.rectenna_curve = curve;
%   results = wpt_farfield_model(params);

    data = readmatrix(filepath);

    % Validate structure
    if size(data, 2) < 2
        error('load_rectenna_curve:InvalidFormat', ...
              'CSV must have at least 2 columns: [P_rx_dBm, efficiency].');
    end

    % Extract first two columns and sort by ascending P_rx
    curve = sortrows(data(:, 1:2), 1);

    % Clamp efficiency to valid range [0, 1]
    curve(:, 2) = max(min(curve(:, 2), 1.0), 0);

    % Remove any rows with NaN (malformed CSV entries)
    valid_rows = ~any(isnan(curve), 2);
    curve = curve(valid_rows, :);

    if size(curve, 1) < 2
        error('load_rectenna_curve:InsufficientData', ...
              'CSV must contain at least 2 valid data points for interpolation.');
    end

    fprintf('  Rectenna curve loaded: %d points, P_rx range [%.1f, %.1f] dBm\n', ...
        size(curve, 1), curve(1, 1), curve(end, 1));
    fprintf('  Efficiency range: [%.3f, %.3f]\n', min(curve(:,2)), max(curve(:,2)));
end
