classdef App_ideal < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                      matlab.ui.Figure
        UIAxes                        matlab.ui.control.UIAxes

        % --- Input Controls: Frequency ---
        FrequencyEditField            matlab.ui.control.NumericEditField
        FrequencyLabel                matlab.ui.control.Label
        FrequencyMHzSlider            matlab.ui.control.Slider

        % --- Input Controls: TX Antenna ---
        TxAntennaEditField            matlab.ui.control.NumericEditField
        TxAntennaLabel                matlab.ui.control.Label
        TxAntennaSlider               matlab.ui.control.Slider

        % --- Input Controls: RX Antenna ---
        RxAntennaEditField            matlab.ui.control.NumericEditField
        RxAntennaLabel                matlab.ui.control.Label
        RxAntennaSlider               matlab.ui.control.Slider

        % --- Input Controls: Max Distance ---
        MaxDistanceEditField          matlab.ui.control.NumericEditField
        MaxDistanceLabel              matlab.ui.control.Label

        % --- Realistic Mode Toggle ---
        RealisticToggleLabel          matlab.ui.control.Label
        RealisticToggle               matlab.ui.control.Switch

        % --- Realistic Constraints Panel ---
        RealisticPanel                matlab.ui.container.Panel
        PathLossExpLabel              matlab.ui.control.Label
        PathLossExpEditField          matlab.ui.control.NumericEditField
        AutoNCheckbox                 matlab.ui.control.CheckBox
        PolarizationLabel             matlab.ui.control.Label
        PolarizationDropDown          matlab.ui.control.DropDown
        LhwLabel                      matlab.ui.control.Label
        LhwEditField                  matlab.ui.control.NumericEditField
        AutoLhwCheckbox               matlab.ui.control.CheckBox
        S11TxLabel                    matlab.ui.control.Label
        S11TxEditField                matlab.ui.control.NumericEditField
        S11RxLabel                    matlab.ui.control.Label
        S11RxEditField                matlab.ui.control.NumericEditField
        AutoRectennaCheckbox          matlab.ui.control.CheckBox
        LoadRectennaButton            matlab.ui.control.Button
        RectennaStatusLabel           matlab.ui.control.Label

        % --- Readout Panel & Fields ---
        ReadoutPanel                  matlab.ui.container.Panel
        NearFieldLabel                matlab.ui.control.Label
        NearFieldValue                matlab.ui.control.Label
        TxGainLabel                   matlab.ui.control.Label
        TxGainValue                   matlab.ui.control.Label
        RxGainLabel                   matlab.ui.control.Label
        RxGainValue                   matlab.ui.control.Label
        QueryDistanceLabel            matlab.ui.control.Label
        QueryDistanceEditField        matlab.ui.control.NumericEditField
        PrxLabel                      matlab.ui.control.Label
        PrxValue                      matlab.ui.control.Label
        EffLabel                      matlab.ui.control.Label
        EffValue                      matlab.ui.control.Label

        % --- Action Buttons ---
        LockGraphforComparisonButton  matlab.ui.control.Button
        ClearGraphButton              matlab.ui.control.Button
    end


    properties (Access = private)
        SavedCurves = {}           % Cell array of saved comparison curve structs
        LastResults = []           % Ideal results cache for readout
        LastRealisticResults = []  % Realistic results cache for readout
        RectennaCurve = []         % Loaded [P_rx_dBm, eff] matrix from CSV
    end

    % Core logic: heuristics, plot update, numerical readout
    methods (Access = private)

        function updateHeuristics(app)
            % Called on frequency change and at startup.
            % Updates Auto-checked fields with heuristic values.
            freq_Hz = app.FrequencyEditField.Value * 1e6;
            h = wpt_heuristics(freq_Hz);

            % Path loss exponent
            if app.AutoNCheckbox.Value
                app.PathLossExpEditField.Value = round(h.n_path, 2);
            end

            % Hardware / insertion loss
            if app.AutoLhwCheckbox.Value
                app.LhwEditField.Value = round(h.L_hardware_dB, 1);
            end

            % Rectenna status display (when auto and no CSV loaded)
            if app.AutoRectennaCheckbox.Value
                app.RectennaStatusLabel.Text = sprintf( ...
                    'Auto: peak=%.1f%% @ %.0f MHz', ...
                    h.eta_peak * 100, freq_Hz / 1e6);
                app.RectennaStatusLabel.FontColor = [0 0.35 0.65];
            end
        end

        function updatePlot(app)
            % 1. Pack base (ideal) params — always n=2, L_hw=0, no losses
            params.freq_Hz      = app.FrequencyEditField.Value * 1e6;
            params.D_tx_m       = app.TxAntennaEditField.Value / 100;
            params.D_rx_m       = app.RxAntennaEditField.Value / 100;
            params.P_tx_dBm     = 20;
            params.n_path       = 2;
            params.eff_rectenna = 0.60;
            params.eta_ap       = 0.60;
            params.d_vec        = linspace(0.1, app.MaxDistanceEditField.Value, 500);
            % Ideal: L_hardware_dB=0 (isfield default), no heuristic rectenna

            % 2. Compute ideal results
            results_ideal = wpt_farfield_model(params);
            app.LastResults = results_ideal;

            % 3. Compute realistic results (if toggle is on)
            realistic_on = strcmp(app.RealisticToggle.Value, 'Realistic');
            results_real = [];
            if realistic_on
                params_real = params;  % Copy base params
                params_real.n_path              = app.PathLossExpEditField.Value;
                params_real.polarization_factor  = app.PolarizationDropDown.Value;
                params_real.S11_tx_dB           = app.S11TxEditField.Value;
                params_real.S11_rx_dB           = app.S11RxEditField.Value;
                params_real.L_hardware_dB       = app.LhwEditField.Value;

                % Rectenna priority: CSV > Heuristic > Flat
                if ~isempty(app.RectennaCurve)
                    params_real.rectenna_curve = app.RectennaCurve;
                elseif app.AutoRectennaCheckbox.Value
                    params_real.use_heuristic_rectenna = true;
                end
                % If neither: falls through to flat eff_rectenna (0.60)

                results_real = wpt_farfield_model(params_real);
            end
            app.LastRealisticResults = results_real;

            % 4. Always clear and rebuild the plot from state
            cla(app.UIAxes, 'reset');
            hold(app.UIAxes, 'on');

            % Color management
            colors = get(groot, 'defaultAxesColorOrder');
            n_colors = size(colors, 1);
            curve_idx = 0;

            % 5. Re-plot all saved comparison curves
            for i = 1:length(app.SavedCurves)
                curve_idx = curve_idx + 1;
                c = colors(mod(curve_idx - 1, n_colors) + 1, :);
                sc = app.SavedCurves{i};

                % Ideal (solid, thin)
                plot(app.UIAxes, sc.d_vec, sc.eff_ideal, '-', ...
                    'LineWidth', 1.5, 'Color', c, ...
                    'DisplayName', sc.label);

                % Realistic (dashed, thin, same color) if saved with it
                if sc.has_realistic
                    plot(app.UIAxes, sc.d_vec, sc.eff_realistic, '--', ...
                        'LineWidth', 1.5, 'Color', c, ...
                        'DisplayName', [sc.label ' (real.)']);
                end
            end

            % 6. Plot the active (live) curve
            curve_idx = curve_idx + 1;
            active_c = colors(mod(curve_idx - 1, n_colors) + 1, :);
            active_label = sprintf('%.1f MHz | TX:%dcm RX:%dcm', ...
                results_ideal.freq_MHz, round(results_ideal.D_tx_cm), ...
                round(results_ideal.D_rx_cm));

            % Active ideal (solid, thick)
            plot(app.UIAxes, results_ideal.d_vec, results_ideal.eff_system_pct, '-', ...
                'LineWidth', 2.5, 'Color', active_c, ...
                'DisplayName', [active_label ' (active)']);

            % Active realistic (dashed, thick, same color)
            if realistic_on && ~isempty(results_real)
                plot(app.UIAxes, results_real.d_vec, results_real.eff_system_pct, '--', ...
                    'LineWidth', 2.5, 'Color', active_c, ...
                    'DisplayName', [active_label ' (active, real.)']);
            end

            % 7. Axes formatting
            legend(app.UIAxes, 'show', 'Location', 'northeast');
            app.UIAxes.XLabel.String = 'Distance (m)';
            app.UIAxes.YLabel.String = 'System Efficiency (%)';
            grid(app.UIAxes, 'on');

            % 8. Title with Near-Field Status
            if all(results_ideal.invalid_indices)
                app.UIAxes.Title.String = sprintf( ...
                    'Warning: Far-field begins at %.2f m (beyond plot range)', ...
                    results_ideal.near_field_boundary_m);
                app.UIAxes.Title.Color = [0.8 0 0];
            else
                app.UIAxes.Title.String = sprintf( ...
                    'Far-Field WPT Link Budget  |  Valid beyond %.2f m', ...
                    results_ideal.near_field_boundary_m);
                app.UIAxes.Title.Color = [0.1 0.1 0.1];
            end

            % 9. Y-axis limits (encompass ALL visible curves)
            all_valid = results_ideal.eff_system_pct(~isnan(results_ideal.eff_system_pct));
            if realistic_on && ~isempty(results_real)
                real_valid = results_real.eff_system_pct(~isnan(results_real.eff_system_pct));
                all_valid = [all_valid, real_valid];
            end
            for i = 1:length(app.SavedCurves)
                sc = app.SavedCurves{i};
                sc_valid = sc.eff_ideal(~isnan(sc.eff_ideal));
                all_valid = [all_valid, sc_valid]; %#ok<AGROW>
                if sc.has_realistic
                    sc_r = sc.eff_realistic(~isnan(sc.eff_realistic));
                    all_valid = [all_valid, sc_r]; %#ok<AGROW>
                end
            end
            if isempty(all_valid)
                ylim(app.UIAxes, [0 1]);
            else
                ylim(app.UIAxes, [0, max(all_valid) * 1.1]);
            end

            % 10. Update Numerical Readouts
            updateReadouts(app, results_ideal, results_real);
        end

        function updateReadouts(app, results_ideal, results_real)
            % Static readouts (always from ideal — gains and NF boundary
            % are antenna/frequency properties, not affected by losses)
            app.NearFieldValue.Text = sprintf('%.3f m', results_ideal.near_field_boundary_m);
            app.TxGainValue.Text    = sprintf('%+.2f dBi', results_ideal.G_tx_dBi);
            app.RxGainValue.Text    = sprintf('%+.2f dBi', results_ideal.G_rx_dBi);

            % Query-distance interpolation
            query_d = app.QueryDistanceEditField.Value;
            if query_d >= min(results_ideal.d_vec) && query_d <= max(results_ideal.d_vec)
                eff_q = interp1(results_ideal.d_vec, results_ideal.eff_system_pct, query_d);
                prx_q = interp1(results_ideal.d_vec, results_ideal.P_rx_dBm,      query_d);

                if isnan(eff_q)
                    app.EffValue.Text = 'In near-field';
                    app.PrxValue.Text = 'N/A';
                    app.PrxLabel.Text = 'P_rx:';
                    app.EffLabel.Text = [char(951) ':'];
                else
                    eff_str = sprintf('%.4f %%', eff_q);
                    prx_str = sprintf('%.2f dBm', prx_q);

                    % Append realistic values if available
                    if ~isempty(results_real)
                        eff_r = interp1(results_real.d_vec, results_real.eff_system_pct, query_d);
                        prx_r = interp1(results_real.d_vec, results_real.P_rx_dBm,      query_d);
                        if ~isnan(eff_r)
                            eff_str = sprintf('%.4f / %.4f %%', eff_q, eff_r);
                            prx_str = sprintf('%.2f / %.2f dBm', prx_q, prx_r);
                        end
                        app.PrxLabel.Text = 'P_rx (I/R):';
                        app.EffLabel.Text = [char(951) ' (I/R):'];
                    else
                        app.PrxLabel.Text = 'P_rx:';
                        app.EffLabel.Text = [char(951) ':'];
                    end

                    app.EffValue.Text = eff_str;
                    app.PrxValue.Text = prx_str;
                end
            else
                app.EffValue.Text = 'Out of range';
                app.PrxValue.Text = char(8212); % em-dash
                app.PrxLabel.Text = 'P_rx:';
                app.EffLabel.Text = [char(951) ':'];
            end
        end

    end

    % Callbacks that handle component events
    methods (Access = private)

        % ---------- Frequency Callbacks ----------
        function FrequencyEditFieldValueChanged(app, event)
            value = app.FrequencyEditField.Value;
            app.FrequencyMHzSlider.Value = log10(value * 1e6);
            updateHeuristics(app);
            updatePlot(app);
        end

        function FrequencyMHzSliderValueChanged(app, event)
            value = app.FrequencyMHzSlider.Value;
            app.FrequencyEditField.Value = round((10^value) / 1e6, 2);
            updateHeuristics(app);
            updatePlot(app);
        end

        % ---------- TX Antenna Callbacks ----------
        function TxAntennaEditFieldValueChanged(app, event)
            value = app.TxAntennaEditField.Value;
            app.TxAntennaSlider.Value = min(value, app.TxAntennaSlider.Limits(2));
            updatePlot(app);
        end

        function TxAntennaSliderValueChanged(app, event)
            app.TxAntennaEditField.Value = round(app.TxAntennaSlider.Value, 1);
            updatePlot(app);
        end

        % ---------- RX Antenna Callbacks ----------
        function RxAntennaEditFieldValueChanged(app, event)
            value = app.RxAntennaEditField.Value;
            app.RxAntennaSlider.Value = min(value, app.RxAntennaSlider.Limits(2));
            updatePlot(app);
        end

        function RxAntennaSliderValueChanged(app, event)
            app.RxAntennaEditField.Value = round(app.RxAntennaSlider.Value, 1);
            updatePlot(app);
        end

        % ---------- Max Distance ----------
        function MaxDistanceEditFieldValueChanged(app, event)
            updatePlot(app);
        end

        % ---------- Query Distance ----------
        function QueryDistanceEditFieldValueChanged(app, event)
            if ~isempty(app.LastResults)
                updateReadouts(app, app.LastResults, app.LastRealisticResults);
            end
        end

        % ---------- Realistic Mode Toggle ----------
        function RealisticToggleValueChanged(app, event)
            if strcmp(app.RealisticToggle.Value, 'Realistic')
                app.RealisticPanel.Visible = 'on';
                updateHeuristics(app);
            else
                app.RealisticPanel.Visible = 'off';
            end
            updatePlot(app);
        end

        % ---------- Realistic Parameter Callbacks ----------
        function PathLossExpEditFieldValueChanged(app, event)
            updatePlot(app);
        end

        function PolarizationDropDownValueChanged(app, event)
            updatePlot(app);
        end

        function S11TxEditFieldValueChanged(app, event)
            updatePlot(app);
        end

        function S11RxEditFieldValueChanged(app, event)
            updatePlot(app);
        end

        function LhwEditFieldValueChanged(app, event)
            updatePlot(app);
        end

        % ---------- Auto Checkbox Callbacks ----------
        function AutoNCheckboxValueChanged(app, event)
            if app.AutoNCheckbox.Value
                app.PathLossExpEditField.Enable = 'off';
                updateHeuristics(app);
            else
                app.PathLossExpEditField.Enable = 'on';
            end
            updatePlot(app);
        end

        function AutoLhwCheckboxValueChanged(app, event)
            if app.AutoLhwCheckbox.Value
                app.LhwEditField.Enable = 'off';
                updateHeuristics(app);
            else
                app.LhwEditField.Enable = 'on';
            end
            updatePlot(app);
        end

        function AutoRectennaCheckboxValueChanged(app, event)
            if app.AutoRectennaCheckbox.Value
                % Return to heuristic mode — clear any loaded CSV
                app.RectennaCurve = [];
                app.LoadRectennaButton.Text = 'Load Rectenna CSV';
                app.LoadRectennaButton.BackgroundColor = [0.85 0.93 1.0];
                updateHeuristics(app);
            else
                % Manual mode — enable CSV loading
                app.LoadRectennaButton.Enable = 'on';
                if isempty(app.RectennaCurve)
                    app.RectennaStatusLabel.Text = 'No curve (using flat 60%)';
                    app.RectennaStatusLabel.FontColor = [0.5 0.5 0.5];
                end
            end
            updatePlot(app);
        end

        % ---------- Load / Clear CSV ----------
        function LoadRectennaButtonPushed(app, event)
            if ~isempty(app.RectennaCurve)
                % CLEAR MODE: remove the loaded CSV
                app.RectennaCurve = [];
                app.LoadRectennaButton.Text = 'Load Rectenna CSV';
                app.LoadRectennaButton.BackgroundColor = [0.85 0.93 1.0];
                app.AutoRectennaCheckbox.Enable = 'on';
                app.RectennaStatusLabel.Text = 'No curve (using flat 60%)';
                app.RectennaStatusLabel.FontColor = [0.5 0.5 0.5];
                updatePlot(app);
                return;
            end

            % LOAD MODE: open file dialog
            [file, path] = uigetfile( ...
                {'*.csv', 'CSV Files (*.csv)'; '*.*', 'All Files'}, ...
                'Select Rectenna Efficiency Curve');
            if isequal(file, 0)
                return;  % User cancelled
            end
            filepath = fullfile(path, file);
            try
                app.RectennaCurve = load_rectenna_curve(filepath);
                app.LoadRectennaButton.Text = 'Clear CSV';
                app.LoadRectennaButton.BackgroundColor = [1.0 0.90 0.90];
                app.AutoRectennaCheckbox.Value = false;
                app.AutoRectennaCheckbox.Enable = 'off';
                app.RectennaStatusLabel.Text = sprintf('CSV: %s (%d pts)', ...
                    file, size(app.RectennaCurve, 1));
                app.RectennaStatusLabel.FontColor = [0 0.5 0];
                updatePlot(app);
            catch err
                app.RectennaStatusLabel.Text = sprintf('Error: %s', err.message);
                app.RectennaStatusLabel.FontColor = [0.8 0 0];
            end
        end

        % ---------- Save / Clear Comparison ----------
        function LockGraphforComparisonButtonPushed(app, event)
            if ~isempty(app.LastResults)
                curve.d_vec = app.LastResults.d_vec;
                curve.eff_ideal = app.LastResults.eff_system_pct;

                if ~isempty(app.LastRealisticResults)
                    curve.eff_realistic = app.LastRealisticResults.eff_system_pct;
                    curve.has_realistic = true;
                else
                    curve.eff_realistic = [];
                    curve.has_realistic = false;
                end

                curve.label = sprintf('[Saved] %.1f MHz | TX:%dcm RX:%dcm', ...
                    app.LastResults.freq_MHz, round(app.LastResults.D_tx_cm), ...
                    round(app.LastResults.D_rx_cm));
                app.SavedCurves{end+1} = curve;
                updatePlot(app);
            end
        end

        function ClearGraphButtonPushed(app, event)
            app.SavedCurves = {};
            updatePlot(app);
        end
    end

    % Component initialization
    methods (Access = private)

        function createComponents(app)

            % ==================== FIGURE ====================
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [80 40 1060 800];
            app.UIFigure.Name = 'WPT Far-Field Link Budget Calculator';
            app.UIFigure.Color = [0.94 0.94 0.96];

            % ==================== PLOT AXES ====================
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, '')
            xlabel(app.UIAxes, 'Distance (m)')
            ylabel(app.UIAxes, 'System Efficiency (%)')
            app.UIAxes.Position = [65 25 950 350];

            % ==================== FREQUENCY CONTROLS ====================
            app.FrequencyEditField = uieditfield(app.UIFigure, 'numeric');
            app.FrequencyEditField.Limits = [10 10000];
            app.FrequencyEditField.ValueChangedFcn = createCallbackFcn(app, @FrequencyEditFieldValueChanged, true);
            app.FrequencyEditField.Position = [20 755 75 22];
            app.FrequencyEditField.Value = 2450;

            app.FrequencyLabel = uilabel(app.UIFigure);
            app.FrequencyLabel.Position = [100 750 80 30];
            app.FrequencyLabel.Text = {'Frequency'; '(MHz)'};

            app.FrequencyMHzSlider = uislider(app.UIFigure);
            app.FrequencyMHzSlider.Limits = [7 10];
            app.FrequencyMHzSlider.MajorTicks = [7 8 9 10];
            app.FrequencyMHzSlider.MajorTickLabels = {'10M', '100M', '1G', '10G'};
            app.FrequencyMHzSlider.ValueChangedFcn = createCallbackFcn(app, @FrequencyMHzSliderValueChanged, true);
            app.FrequencyMHzSlider.Position = [190 768 230 3];
            app.FrequencyMHzSlider.Value = log10(2450e6);

            % ==================== TX ANTENNA CONTROLS ====================
            app.TxAntennaEditField = uieditfield(app.UIFigure, 'numeric');
            app.TxAntennaEditField.Limits = [1 500];
            app.TxAntennaEditField.ValueChangedFcn = createCallbackFcn(app, @TxAntennaEditFieldValueChanged, true);
            app.TxAntennaEditField.Position = [20 705 75 22];
            app.TxAntennaEditField.Value = 10;

            app.TxAntennaLabel = uilabel(app.UIFigure);
            app.TxAntennaLabel.Position = [100 700 82 30];
            app.TxAntennaLabel.Text = {'TX Antenna'; '(cm)'};

            app.TxAntennaSlider = uislider(app.UIFigure);
            app.TxAntennaSlider.Limits = [1 100];
            app.TxAntennaSlider.ValueChangedFcn = createCallbackFcn(app, @TxAntennaSliderValueChanged, true);
            app.TxAntennaSlider.Position = [190 718 230 3];
            app.TxAntennaSlider.Value = 10;

            % ==================== RX ANTENNA CONTROLS ====================
            app.RxAntennaEditField = uieditfield(app.UIFigure, 'numeric');
            app.RxAntennaEditField.Limits = [1 500];
            app.RxAntennaEditField.ValueChangedFcn = createCallbackFcn(app, @RxAntennaEditFieldValueChanged, true);
            app.RxAntennaEditField.Position = [20 655 75 22];
            app.RxAntennaEditField.Value = 5;

            app.RxAntennaLabel = uilabel(app.UIFigure);
            app.RxAntennaLabel.Position = [100 650 82 30];
            app.RxAntennaLabel.Text = {'RX Antenna'; '(cm)'};

            app.RxAntennaSlider = uislider(app.UIFigure);
            app.RxAntennaSlider.Limits = [1 100];
            app.RxAntennaSlider.ValueChangedFcn = createCallbackFcn(app, @RxAntennaSliderValueChanged, true);
            app.RxAntennaSlider.Position = [190 668 230 3];
            app.RxAntennaSlider.Value = 5;

            % ==================== MAX DISTANCE ====================
            app.MaxDistanceEditField = uieditfield(app.UIFigure, 'numeric');
            app.MaxDistanceEditField.Limits = [0.5 1000];
            app.MaxDistanceEditField.ValueChangedFcn = createCallbackFcn(app, @MaxDistanceEditFieldValueChanged, true);
            app.MaxDistanceEditField.Position = [20 615 75 22];
            app.MaxDistanceEditField.Value = 5;

            app.MaxDistanceLabel = uilabel(app.UIFigure);
            app.MaxDistanceLabel.Position = [100 615 110 22];
            app.MaxDistanceLabel.Text = 'Max Distance (m)';

            % ==================== REALISTIC MODE TOGGLE ====================
            % Label positioned ABOVE the switch to prevent text overlap
            app.RealisticToggleLabel = uilabel(app.UIFigure);
            app.RealisticToggleLabel.Position = [20 585 120 22];
            app.RealisticToggleLabel.Text = 'Realistic Mode:';
            app.RealisticToggleLabel.FontWeight = 'bold';

            app.RealisticToggle = uiswitch(app.UIFigure, 'slider');
            app.RealisticToggle.Items = {'Ideal', 'Realistic'};
            app.RealisticToggle.Value = 'Ideal';
            app.RealisticToggle.ValueChangedFcn = createCallbackFcn(app, @RealisticToggleValueChanged, true);
            app.RealisticToggle.Position = [55 558 45 20];

            % ==================== REALISTIC CONSTRAINTS PANEL ====================
            app.RealisticPanel = uipanel(app.UIFigure);
            app.RealisticPanel.Title = 'Realistic Constraints';
            app.RealisticPanel.FontWeight = 'bold';
            app.RealisticPanel.ForegroundColor = [0.6 0.3 0.1];
            app.RealisticPanel.Position = [20 390 430 155];
            app.RealisticPanel.Visible = 'off';

            % --- Row 1: Path Loss Exponent + Auto + Polarization ---
            app.PathLossExpLabel = uilabel(app.RealisticPanel);
            app.PathLossExpLabel.Position = [10 100 90 22];
            app.PathLossExpLabel.Text = 'Path Loss (n):';

            app.PathLossExpEditField = uieditfield(app.RealisticPanel, 'numeric');
            app.PathLossExpEditField.Limits = [2.0 6.0];
            app.PathLossExpEditField.ValueChangedFcn = createCallbackFcn(app, @PathLossExpEditFieldValueChanged, true);
            app.PathLossExpEditField.Position = [105 100 50 22];
            app.PathLossExpEditField.Value = 2.0;
            app.PathLossExpEditField.Enable = 'off';  % Auto by default

            app.AutoNCheckbox = uicheckbox(app.RealisticPanel);
            app.AutoNCheckbox.Text = 'Auto';
            app.AutoNCheckbox.Value = true;
            app.AutoNCheckbox.ValueChangedFcn = createCallbackFcn(app, @AutoNCheckboxValueChanged, true);
            app.AutoNCheckbox.Position = [162 100 50 22];

            app.PolarizationLabel = uilabel(app.RealisticPanel);
            app.PolarizationLabel.Position = [225 100 78 22];
            app.PolarizationLabel.Text = 'Polarization:';

            app.PolarizationDropDown = uidropdown(app.RealisticPanel);
            app.PolarizationDropDown.Items = {'Co-polarized', '45° Mismatch', 'Cross-polarized'};
            app.PolarizationDropDown.ItemsData = [1.0, 0.5, 0.01];
            app.PolarizationDropDown.Value = 1.0;
            app.PolarizationDropDown.ValueChangedFcn = createCallbackFcn(app, @PolarizationDropDownValueChanged, true);
            app.PolarizationDropDown.Position = [308 100 112 22];

            % --- Row 2: Hardware Loss + Auto ---
            app.LhwLabel = uilabel(app.RealisticPanel);
            app.LhwLabel.Position = [10 68 90 22];
            app.LhwLabel.Text = 'L_hw (dB):';

            app.LhwEditField = uieditfield(app.RealisticPanel, 'numeric');
            app.LhwEditField.Limits = [0 10];
            app.LhwEditField.ValueChangedFcn = createCallbackFcn(app, @LhwEditFieldValueChanged, true);
            app.LhwEditField.Position = [105 68 50 22];
            app.LhwEditField.Value = 2.0;
            app.LhwEditField.Enable = 'off';  % Auto by default

            app.AutoLhwCheckbox = uicheckbox(app.RealisticPanel);
            app.AutoLhwCheckbox.Text = 'Auto';
            app.AutoLhwCheckbox.Value = true;
            app.AutoLhwCheckbox.ValueChangedFcn = createCallbackFcn(app, @AutoLhwCheckboxValueChanged, true);
            app.AutoLhwCheckbox.Position = [162 68 50 22];

            % --- Row 3: S11 TX + S11 RX ---
            app.S11TxLabel = uilabel(app.RealisticPanel);
            app.S11TxLabel.Position = [10 38 120 22];
            app.S11TxLabel.Text = 'S11 TX (dB, e.g. -10):';

            app.S11TxEditField = uieditfield(app.RealisticPanel, 'numeric');
            app.S11TxEditField.Limits = [-60 0];
            app.S11TxEditField.ValueChangedFcn = createCallbackFcn(app, @S11TxEditFieldValueChanged, true);
            app.S11TxEditField.Position = [135 38 55 22];
            app.S11TxEditField.Value = -20;

            app.S11RxLabel = uilabel(app.RealisticPanel);
            app.S11RxLabel.Position = [200 38 120 22];
            app.S11RxLabel.Text = 'S11 RX (dB, e.g. -10):';

            app.S11RxEditField = uieditfield(app.RealisticPanel, 'numeric');
            app.S11RxEditField.Limits = [-60 0];
            app.S11RxEditField.ValueChangedFcn = createCallbackFcn(app, @S11RxEditFieldValueChanged, true);
            app.S11RxEditField.Position = [325 38 55 22];
            app.S11RxEditField.Value = -20;

            % --- Row 4: Rectenna Auto + Load/Clear CSV + Status ---
            app.AutoRectennaCheckbox = uicheckbox(app.RealisticPanel);
            app.AutoRectennaCheckbox.Text = 'Rectenna Auto';
            app.AutoRectennaCheckbox.Value = true;
            app.AutoRectennaCheckbox.ValueChangedFcn = createCallbackFcn(app, @AutoRectennaCheckboxValueChanged, true);
            app.AutoRectennaCheckbox.Position = [10 8 100 22];

            app.LoadRectennaButton = uibutton(app.RealisticPanel, 'push');
            app.LoadRectennaButton.ButtonPushedFcn = createCallbackFcn(app, @LoadRectennaButtonPushed, true);
            app.LoadRectennaButton.Position = [120 6 130 26];
            app.LoadRectennaButton.Text = 'Load Rectenna CSV';
            app.LoadRectennaButton.BackgroundColor = [0.85 0.93 1.0];

            app.RectennaStatusLabel = uilabel(app.RealisticPanel);
            app.RectennaStatusLabel.Position = [255 8 170 22];
            app.RectennaStatusLabel.Text = 'Auto: initializing...';
            app.RectennaStatusLabel.FontColor = [0.5 0.5 0.5];

            % ==================== READOUT PANEL ====================
            app.ReadoutPanel = uipanel(app.UIFigure);
            app.ReadoutPanel.Title = 'Link Budget Readout';
            app.ReadoutPanel.FontWeight = 'bold';
            app.ReadoutPanel.Position = [510 590 350 205];

            % Near-field boundary
            app.NearFieldLabel = uilabel(app.ReadoutPanel);
            app.NearFieldLabel.Position = [10 155 140 22];
            app.NearFieldLabel.Text = 'Near-Field Boundary:';
            app.NearFieldLabel.FontWeight = 'bold';

            app.NearFieldValue = uilabel(app.ReadoutPanel);
            app.NearFieldValue.Position = [160 155 170 22];
            app.NearFieldValue.Text = '-- m';
            app.NearFieldValue.FontColor = [0 0.35 0.65];

            % TX Gain
            app.TxGainLabel = uilabel(app.ReadoutPanel);
            app.TxGainLabel.Position = [10 130 65 22];
            app.TxGainLabel.Text = 'TX Gain:';
            app.TxGainLabel.FontWeight = 'bold';

            app.TxGainValue = uilabel(app.ReadoutPanel);
            app.TxGainValue.Position = [80 130 100 22];
            app.TxGainValue.Text = '-- dBi';
            app.TxGainValue.FontColor = [0 0.35 0.65];

            % RX Gain
            app.RxGainLabel = uilabel(app.ReadoutPanel);
            app.RxGainLabel.Position = [10 105 65 22];
            app.RxGainLabel.Text = 'RX Gain:';
            app.RxGainLabel.FontWeight = 'bold';

            app.RxGainValue = uilabel(app.ReadoutPanel);
            app.RxGainValue.Position = [80 105 100 22];
            app.RxGainValue.Text = '-- dBi';
            app.RxGainValue.FontColor = [0 0.35 0.65];

            % Query distance
            app.QueryDistanceLabel = uilabel(app.ReadoutPanel);
            app.QueryDistanceLabel.Position = [10 73 120 22];
            app.QueryDistanceLabel.Text = 'Query Distance (m):';
            app.QueryDistanceLabel.FontWeight = 'bold';

            app.QueryDistanceEditField = uieditfield(app.ReadoutPanel, 'numeric');
            app.QueryDistanceEditField.Limits = [0.01 10000];
            app.QueryDistanceEditField.ValueChangedFcn = createCallbackFcn(app, @QueryDistanceEditFieldValueChanged, true);
            app.QueryDistanceEditField.Position = [140 73 55 22];
            app.QueryDistanceEditField.Value = 1;

            % P_rx readout
            app.PrxLabel = uilabel(app.ReadoutPanel);
            app.PrxLabel.Position = [10 42 85 22];
            app.PrxLabel.Text = 'P_rx:';
            app.PrxLabel.FontWeight = 'bold';

            app.PrxValue = uilabel(app.ReadoutPanel);
            app.PrxValue.Position = [100 42 240 22];
            app.PrxValue.Text = '-- dBm';
            app.PrxValue.FontColor = [0 0.35 0.65];

            % Efficiency readout
            app.EffLabel = uilabel(app.ReadoutPanel);
            app.EffLabel.Position = [10 12 85 22];
            app.EffLabel.FontWeight = 'bold';
            app.EffLabel.Text = [char(951) ':'];

            app.EffValue = uilabel(app.ReadoutPanel);
            app.EffValue.Position = [100 12 240 22];
            app.EffValue.Text = '-- %';
            app.EffValue.FontColor = [0 0.35 0.65];

            % ==================== ACTION BUTTONS ====================
            app.LockGraphforComparisonButton = uibutton(app.UIFigure, 'push');
            app.LockGraphforComparisonButton.ButtonPushedFcn = createCallbackFcn(app, @LockGraphforComparisonButtonPushed, true);
            app.LockGraphforComparisonButton.Position = [870 755 175 30];
            app.LockGraphforComparisonButton.Text = 'Save for Comparison';
            app.LockGraphforComparisonButton.BackgroundColor = [0.85 0.93 1.0];

            app.ClearGraphButton = uibutton(app.UIFigure, 'push');
            app.ClearGraphButton.ButtonPushedFcn = createCallbackFcn(app, @ClearGraphButtonPushed, true);
            app.ClearGraphButton.Position = [870 715 175 30];
            app.ClearGraphButton.Text = 'Clear Graph';
            app.ClearGraphButton.BackgroundColor = [1.0 0.90 0.90];

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        function app = App_ideal
            createComponents(app)
            registerApp(app, app.UIFigure)

            % Populate auto fields from default frequency BEFORE first plot
            updateHeuristics(app)
            updatePlot(app)

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure)
        end
    end
end