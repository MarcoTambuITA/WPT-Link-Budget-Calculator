# Engineering Report: Interactive WPT Link Budget Calculator (Phase 1 to Phase 2.5)

This report details the evolution of the Interactive Wireless Power Transfer (WPT) Link Budget Calculator from a basic mathematical prototype to a physically rigorous model. The calculator is implemented in MATLAB App Designer and is designed to predict WPT efficiency profiles across a wide frequency range (10 MHz to 5.8 GHz). 

The ultimate goal of this tool is to predict the **efficiency crossover point** between far-field (radiative) WPT and near-field (inductive/resonant) WPT. These predictions will be validated experimentally using a NanoVNA for mismatch measurements ($S_{11}$) and an **HSMS-2850 zero-bias Schottky diode rectenna** circuit.

---

## 1. Core Physics & Mathematical Framework

The physics engine is fully decoupled from the UI. It takes a parameters structure `params` and returns a calculated results structure `results`. The core formulas implemented in the engine are detailed below.

### 1.1. Antenna Aperture Gain
Assuming circular aperture antennas (typical for high-frequency microwave dishes or patch arrays), the directive gain is calculated using:
$$G = \frac{\pi^2 \eta_{ap} D^2}{\lambda^2}$$

In decibels relative to isotropic ($dBi$):
$$G_{dBi} = 10 \log_{10}(G)$$

Where:
*   $\eta_{ap}$ is the aperture efficiency (default: $0.60$).
*   $D$ is the antenna diameter in meters ($D_{tx}$ and $D_{rx}$ are controlled independently).
*   $\lambda = c / f$ is the operating wavelength.

*MATLAB Implementation:*
```matlab
G_tx_linear = (pi^2 * params.eta_ap * params.D_tx_m^2) / lambda^2;
G_rx_linear = (pi^2 * params.eta_ap * params.D_rx_m^2) / lambda^2;
G_tx_dBi = 10 * log10(G_tx_linear);
G_rx_dBi = 10 * log10(G_rx_linear);
```
*Design Note:* We do not clamp the gain to $0\text{ dBi}$ or $1$. Electrically small aperture diameters correctly yield sub-isotropic gains (negative dBi values), which naturally suppresses system efficiency at low frequencies.

---

### 1.2. Three-Layer Near-Field Boundary Masking
Far-field equations (such as Friis transmission) diverge and violate energy conservation when distance $d \rightarrow 0$. To prevent unphysical efficiency values, the calculator computes the transition boundary ($d_{boundary}$) as the maximum of three distinct physical limits:

1.  **Fraunhofer Distance (Aperture Limit):**
    $$d_{Fraunhofer} = \frac{2 D_{max}^2}{\lambda}$$
    where $D_{max} = \max(D_{tx}, D_{rx})$.
2.  **Radiansphere Limit (Reactive Boundary):**
    $$d_{Radiansphere} = \frac{\lambda}{2\pi}$$
3.  **Aperture Capture Limit:**
    $$d_{Capture} = \sqrt{\frac{A_{e,rx}}{4\pi}}$$
    where $A_{e,rx} = \frac{\lambda^2 G_{rx}}{4\pi}$ is the effective aperture area.

$$d_{boundary} = \max\left( d_{Fraunhofer}, d_{Radiansphere}, d_{Capture} \right)$$

*MATLAB Implementation:*
```matlab
D_max = max(params.D_tx_m, params.D_rx_m);
fraunhofer_dist = (2 * D_max^2) / lambda;
radiansphere_dist = lambda / (2 * pi);
Ae_rx = (lambda^2 * G_rx_linear) / (4 * pi);
aperture_capture_dist = sqrt(Ae_rx / (4 * pi));
near_field_boundary_m = max([fraunhofer_dist, radiansphere_dist, aperture_capture_dist]);
```
Any points inside the near-field region ($d < d_{boundary}$) are masked out as `NaN`, ensuring that far-field path loss models are only evaluated in valid regions.

---

### 1.3. Realistic Losses: Impedance Mismatch & Polarization
Real-world deployments suffer from polarization and impedance mismatches. The model integrates these as follows:

*   **Impedance Mismatch ($S_{11}$):** Derived from the return loss at each antenna terminal.
    $$|\Gamma|^2 = 10^{\frac{S_{11}}{10}}$$
    $$\text{Mismatch Loss (dB)} = 10 \log_{10}(1 - |\Gamma|^2)$$
*   **Polarization Loss ($F_{pol}$):** User selects a polarization alignment factor (e.g., $1.0$ for perfect alignment, $0.5$ for $45^\circ$ mismatch, $0$ for cross-polarization).
    $$\text{Polarization Loss (dB)} = 10 \log_{10}(F_{pol})$$

*MATLAB Implementation:*
```matlab
gamma_sq_tx = 10^(params.S11_tx_dB / 10);
gamma_sq_rx = 10^(params.S11_rx_dB / 10);
mismatch_tx_dB = 10 * log10(1 - gamma_sq_tx);
mismatch_rx_dB = 10 * log10(1 - gamma_sq_rx);
pol_loss_dB = 10 * log10(max(params.polarization_factor, 1e-10));
```

---

### 1.4. The Close-In (CI) Reference Distance Path Loss Model
*The "Free Energy" Bug:* Standard log-distance path loss is expressed as:
$$PL(d) = PL(1\text{m}) + 10 n \log_{10}(d)$$
When the path loss exponent $n > 2$ and the evaluation distance $d < 1\text{ m}$, the logarithmic term $\log_{10}(d)$ becomes negative. Consequently, the term $10 n \log_{10}(d)$ subtracts *more* loss than the ideal $20 \log_{10}(d)$ case, causing the realistic curve to spike above the ideal curve. This violates energy conservation.

*The Solution:* We implemented a **Close-In (CI) Reference Distance Model** anchoring the reference distance $d_0$ dynamically at the near-field boundary:
$$PL_{CI}(d) = FSPL(d_0) + 10 n \log_{10}\left(\frac{d}{d_0}\right) + L_{hardware}$$
where $FSPL(d_0) = 20 \log_{10}\left(\frac{4 \pi d_0}{\lambda}\right)$ is the standard free-space path loss at the boundary $d_0$.

**Why this resolves the bug:**
1.  Since $d_0$ is the minimum boundary for far-field evaluations, the ratio $d/d_0 \geq 1$ for all valid data points. Thus, $\log_{10}(d/d_0) \geq 0$ always.
2.  With $n \geq 2$, the path loss exponent term is always non-negative, guaranteeing that realistic path loss is greater than or equal to ideal path loss at any distance.
3.  When $n = 2$ and $L_{hardware} = 0$, the equation reduces exactly to standard FSPL:
    $$PL_{CI}(d) = 20 \log_{10}\left(\frac{4 \pi d_0}{\lambda}\right) + 20 \log_{10}\left(\frac{d}{d_0}\right) = 20 \log_{10}\left(\frac{4 \pi d}{\lambda}\right)$$
    This provides perfect backward compatibility.

*MATLAB Implementation:*
```matlab
d0 = near_field_boundary_m;
FSPL_d0 = 20 * log10(4 * pi * d0 / lambda);
path_loss_dB = FSPL_d0 ...
               + 10 * params.n_path * log10(params.d_vec / d0) ...
               + params.L_hardware_dB;
```

---

## 2. The Heuristic Engine (Smart Defaults)

To make the app interactive and physically meaningful, we engineered a standalone heuristic function `wpt_heuristics.m`. It calculates smart defaults dynamically based on the operating frequency:

### 2.1. Path Loss Exponent ($n$)
As frequency increases, alignment tolerances tighten and scattering effects intensify. We scale $n$ log-linearly:
$$n = 2.0 + 0.15 \log_{10}\left(\frac{f}{10\text{ MHz}}\right)$$
Clamped to the range $[2.0, 3.0]$.

### 2.2. Hardware Loss ($L_{hardware}$)
Cable attenuation, connector insertion loss, and PCB trace losses rise with frequency:
$$L_{hardware} = 2.0 + 0.5 \log_{10}\left(\frac{f}{10\text{ MHz}}\right)\text{ dB}$$
Clamped to the range $[1.0, 4.0]\text{ dB}$.

### 2.3. Rectenna Efficiency: HSMS-2850 Diode Model
Schottky diode performance is non-linear and suffers from high-frequency parasitics and low-power conduction thresholds. We implement a two-factor model:

1.  **Junction Capacitance ($C_j$) Rolloff:**
    $$\eta_{peak}(f) = \frac{\eta_{max}}{1 + \left(\frac{f}{f_{rolloff}}\right)^2}$$
    where $\eta_{max} = 0.65$ (peak efficiency at low frequency) and $f_{rolloff} = 5.0\text{ GHz}$. This yields $\sim 27.7\%$ peak efficiency at $5.8\text{ GHz}$, matching experimental benchmarks for the HSMS-2850.
2.  **Sigmoid Turn-on Power Sensitivity:**
    $$\eta(P_{rx}) = \frac{\eta_{peak}(f)}{1 + \exp\left(-\frac{P_{rx} - P_{thresh}}{P_{slope}}\right)}$$
    where $P_{thresh} = -20\text{ dBm}$ (diode turn-on midpoint) and $P_{slope} = 8\text{ dBm}$ (turn-on steepness factor).

*Heuristic Engine Output Table:*
| Frequency | Path Loss Exponent ($n$) | Hardware Loss ($L_{hw}$) | Diode Peak Efficiency ($\eta_{peak}$) |
|---|---|---|---|
| **10 MHz** | 2.00 | 2.00 dB | 64.99% |
| **915 MHz** | 2.29 | 2.98 dB | 62.88% |
| **2.45 GHz** | 2.36 | 3.19 dB | 52.41% |
| **5.8 GHz** | 2.42 | 3.38 dB | 27.73% |

---

### 2.4. Three-Tier Rectenna Priority
When computing DC output power, the calculator checks for inputs in this order:
1.  **LTspice CSV curve (Highest Priority):** Interpolates a user-loaded `[P_rx_dBm, efficiency]` dataset (representing simulated or measured rectenna curves). It enforces a strict boundary policy:
    *   *Below minimum power:* Efficiency $= 0$ (diode fails to turn on).
    *   *Above maximum power:* Efficiency is capped at the maximum table value (plateau).
2.  **Heuristic Sigmoid Model:** Triggered if "Auto Rectenna" is checked.
3.  **Flat Efficiency (Lowest Priority):** Fallback value (e.g. flat $60\%$) for basic analysis.

---

## 3. UI State Machine & Comparative Visualization

The UI features dual-mode plotting (Ideal vs. Realistic) with a comparison locking feature:

*   **Decoupled Layout:** The upper panel contains independent sliders and edit fields for TX and RX diameters ($[1, 100]\text{ cm}$ visual sliders, manual inputs up to $500\text{ cm}$). The lower panel contains realistic loss fields.
*   **Auto Checkbox State Machine:** Separate "Auto" checkboxes exist for Path Loss ($n$), Hardware Loss ($L_{hw}$), and Rectenna model.
    *   *Checked:* The parameter input is locked (`Enable = 'off'`) and tracks the frequency heuristics.
    *   *Unchecked:* The parameter unlocks, freezing its value at the current default.
*   **SavedCurves and Visual Encoding:** When "Lock Graph for Comparison" is pushed, the active curves (ideal and realistic) are cloned into `SavedCurves`.
    *   *Active Curve:* Plotted with a thick line width ($2.5\text{ pt}$).
    *   *Saved Curves:* Plotted with thin line widths ($1.5\text{ pt}$).
    *   *Ideal Curves:* Rendered as solid lines.
    *   *Realistic Curves:* Rendered as dashed lines.
    *   *Colors:* Rebuilt dynamically using the axes' color order to ensure saved curves retain unique, matching colors for their ideal/realistic pairs.

---

## 4. Verification Suite Results

A script-based verification suite (`verify_model.m`) runs 14 distinct tests containing 20 assertions to guarantee mathematical and logical correctness. All 20 tests currently pass:

1.  **Test 1 (Gains & Link Budget):** Validates gains and Friis link budgets at 2.45 GHz against manual hand calculations to machine precision.
2.  **Test 2 (NF Boundary Masking):** Confirms that efficiency is masked (`NaN`) at $d < d_{boundary}$ and valid at $d > d_{boundary}$.
3.  **Test 3 (Energy Conservation):** Assures system efficiency never exceeds $100\%$.
4.  **Test 4 (Low Frequency Boundary):** Checks that radiansphere masking dominates at 10 MHz ($\sim 4.77\text{ m}$ boundary).
5.  **Test 5 (High Gain Dishes):** Validates the Fraunhofer boundary dominance at 5.8 GHz with larger dishes.
6.  **Test 6 (Symmetry Check):** Validates that $G_{tx} = G_{rx}$ when diameters are symmetric.
7.  **Test 7 (Backward Compatibility):** Confirms that omitting realistic arguments falls back to identical, lossless defaults.
8.  **Test 8 (Loss Suppression):** Verifies that realistic efficiency is strictly less than or equal to ideal efficiency.
9.  **Test 9 (S11 Return Loss):** Verifies that $S_{11} = -10\text{ dB}$ maps exactly to $-0.457\text{ dB}$ mismatch loss.
10. **Test 10 (CSV Interpolation):** Confirms interpolation logic and clamps.
11. **Test 11 (CI Model Validation):** Validates that realistic curves never exceed ideal curves for $n > 2$ at sub-meter distances (no "free energy").
12. **Test 12 (CI to FSPL Equivalence):** Proves that CI path loss is identical to standard FSPL when $n = 2$ and $L_{hw} = 0$.
13. **Test 13 (Heuristic Calibration):** Verifies monotonic scaling and 5.8 GHz Schottky diode rolloff calibration.
14. **Test 14 (Sigmoid Turn-on):** Validates sigmoid shape and turn-on thresholds.

---

## 5. Phase 3 Roadmap: Near-Field Inductive Coupling

The next phase aims to bridge the far-field model with a near-field inductive coupling model, calculating the crossover point where inductive efficiency drops below radiative efficiency.

### 5.1. Inductive Physics & Mutual Inductance
The near-field link will be modeled as a pair of coupled coils. The mutual inductance ($M$) between two coaxial circular loops is computed using the **Neumann formula**:
$$M = \mu_0 \sqrt{r_{tx} r_{rx}} \left[ \left(\frac{2}{k} - k\right) K(k) - \frac{2}{k} E(k) \right]$$

Where:
*   $r_{tx}, r_{rx}$ are the coil radii.
*   $d$ is the coaxial separation distance.
*   $k^2 = \frac{4 r_{tx} r_{rx}}{(r_{tx} + r_{rx})^2 + d^2}$ is the coupling parameter.
*   $K(k)$ and $E(k)$ are the **complete elliptic integrals of the first and second kind**, respectively.

In MATLAB, these are calculated using the built-in function `[K, E] = ellipke(k^2)`.

From the mutual inductance $M$, we find the coupling coefficient ($k_{coil}$):
$$k_{coil} = \frac{M}{\sqrt{L_{tx} L_{rx}}}$$

### 5.2. Double-Tier UI Input Layout
We plan to introduce a toggle in the UI to allow two methods of defining coil parameters:
1.  **Physical-First Mode:** User enters coil parameters:
    *   Coil radius ($r_{tx}, r_{rx}$)
    *   Number of turns ($N_{tx}, N_{rx}$)
    *   Wire diameter/gauge (AWG)
    The app then calculates $L$, $Q$, and $k_{coil}$ using analytical coil inductance and AC resistance formulas.
2.  **Expert Override Mode:** User enters electrical parameters directly:
    *   Inductances ($L_{tx}, L_{rx}$)
    *   Quality factors ($Q_{tx}, Q_{rx}$)
    *   Coupling coefficient ($k_{coil}$)

### 5.3. Link Efficiency & Crossover Plotting
The maximum power transfer efficiency of a coupled inductive link is determined by the figure of merit $U = k_{coil} \sqrt{Q_{tx} Q_{rx}}$:
$$\eta_{inductive} = \frac{U^2}{\left(1 + \sqrt{1 + U^2}\right)^2}$$

The app will overlay this near-field inductive efficiency curve onto the far-field radiative curve over the distance vector. This will display a clear visual **crossover point**, enabling researchers to identify the exact distance at which radiative WPT outperforms inductive coupling for a given frequency and antenna/coil size.

---

## 6. Feedback & Discussion Topics for Gemini Pro

We are sharing this summary with Gemini Pro to solicit feedback on the following areas before writing the Phase 3 code:

1.  **Elliptic Integral Implementation:** Are there any numerical stability issues with MATLAB's `ellipke` when $d \rightarrow 0$ (coupling parameter $k \rightarrow 1$), and what is the best way to handle very short distances?
2.  **Multi-Turn Coil Self-Inductance:** What is the most accurate closed-form formula to calculate the self-inductance $L$ of flat spiral coils or single-layer solenoids in MATLAB for the "Physical-First" mode?
3.  **Crossover Region Physics:** Is there a transitional "mid-field" region (radiative near-field/Fresnel zone) we should model to bridge the gap between inductive coupling and far-field Friis transmission? How can we model the coupling between a wire loop (inductive) and an aperture antenna (far-field) if a user mixes TX and RX types?
4.  **HSMS-2850 Diode Model Improvements:** Does the current sigmoid turn-on capture the diode's reverse breakdown behavior or temperature effects? Should we implement a harmonic balance or simplified SPICE-based look-up engine inside MATLAB to refine the rectenna efficiency?
