# Synthetic Thermal RSO Dataset Generator

A highly configurable, physics-based generation pipeline for rendering synthetic long-wave infrared (LWIR) imagery of Resident Space Objects (RSOs) in Low Earth Orbit (LEO). This tool is explicitly designed to generate robust datasets for training deep learning perception models on tasks including **detection, tracking, pose estimation, and component segmentation**.

Each generated sequence provides high-fidelity, 16-bit apparent-temperature frames alongside pixel-perfect component masks, bounding boxes, relative pose, and range metrics.

---

## 🚀 Quick Start

The entire generation pipeline is controlled through a single configuration file (`config.m`) and executed via a single entry point.

1. **Configure your run:** Open `config.m` to set dataset size, spacecraft models, trajectory brackets, and sensor parameters.
2. **Execute the pipeline:** 
   ```matlab
   run_generation
   ```

> [!TIP]
> **Debug Mode**: Set `cfg.debug_mode = true;` in `config.m` to run a fast verification pass (generates only 1 sequence of 5 frames per spacecraft) before committing to a full dataset render.

---

## 📂 Project Architecture

```text
final_main_thermal_dataset/
├── run_generation.m      # Pipeline entry point
├── config.m              # Master configuration file (ALL settings live here)
│
├── src/
│   ├── scenario/         # Logic for target positioning, tumbling, and lighting
│   │   └── trajectories/ # Physical motion models (straight, flyby, orbit, CW)
│   ├── target/           # Spacecraft CAD processing and thermal database
│   ├── render/           # Scene rasterization (Target + GeoGlobe Earth + Stars)
│   ├── sensor/           # Camera intrinsics, noise (NETD, Blur), and radiometry
│   ├── io/               # Dataset compilation and JSON/CSV writing
│   └── qa/               # Quality assurance and verification bounding
│
├── data/                 
│   ├── spacecraft/       # Spacecraft geometries, component maps, thermal props
│   └── star_catalog/     # Hipparcos star field data
│
├── dataset/              # Default output directory for generated datasets
├── tests/                # Unit/Regression tests (run `run_all_tests.m`)
└── validation/           # HIL (Hardware-in-the-Loop) cross-checks
```

---

## ⚙️ How to Configure (`config.m`)

The pipeline is completely deterministic and modular. Modify `config.m` to adjust generation parameters without touching the core source code.

| Goal | Where to Edit |
|---|---|
| **Change Dataset Size** | `cfg.num_sequences`, `cfg.frames_per_sequence` |
| **Select Spacecraft** | `cfg.spacecraft` (e.g., `{'M4V', 'Rosetta'}`) |
| **Modify Trajectories** | `cfg.distance_scenarios` (supports 10km to 100m) |
| **Adjust Camera Specs** | `cfg.camera` (Focal length, pitch, resolution, FOV) |
| **Tweak Noise Profiles**| `cfg.sensor` (NETD, Blur, Save window T_min/T_max) |
| **Edit Material Temps** | `src/target/thermal_database.m` |

---

## 🛰️ Physics & Scenarios

The scenario generator (`src/scenario/generate_random_scenario.m`) automatically scales difficulty and trajectory physics based on your configurations.

### Distance Brackets & Trajectories
The pipeline dynamically restricts trajectory types based on physical constraints. The default brackets span from 10km down to 100m:
- **Far Field (10km - 1km):** Utilizes linear `straight` approaches and `flyby` paths.
- **Close Proximity (1km - 100m):** Simulates complex coupled dynamics like `cw_relative_motion` (Clohessy-Wiltshire), `orbit` (inspection fly-arounds), `lateral`, and `station_keeping`.

### Attitude & Tumbling
Targets are spawned with physically representative tumbling profiles, evaluated through rotational kinematics:
- `Stable` (0.0 rad/s)
- `Very Slow Tumbling` (0.01 rad/s)
- `Slow Tumbling` (0.05 rad/s)
- `Medium Tumbling` (0.15 rad/s)
- `Fast Tumbling` (0.50 rad/s)
- `Multi-Axis Tumbling` (0.25 rad/s with randomized axes)

### Illumination
Solar phase is drawn continuously over `[0, 180]` degrees to ensure uniform coverage across all lighting geometries (front-lit, back-lit, and edge-lit).

---

## 📊 Dataset Outputs

Generated datasets are organized intuitively for direct integration into machine learning dataloaders.

```text
dataset/
├── dataset_info.json             # Global constants, radiometry, and taxonomy
└── <spacecraft_name>/
    ├── class_map.json            # Semantic IDs → Component Names
    ├── class_colors.json         # Component Names → RGB (for visual masks)
    └── sequences/SequenceNNN/
        ├── thermal_gray/         # 16-bit Apparent Temperature (Ground Truth)
        ├── thermal_rgb/          # Display derivative (Visual only)
        ├── component_masks/      # Pixel-perfect semantic segmentation maps
        ├── labels.csv            # 21 columns of per-frame annotations (Pose, Range)
        ├── metadata.json         # Sequence-level variables (Lighting, Tumbling)
        └── component_annotations.json # Bounding boxes per component
```

### Understanding the Thermal Pixel
The primary training artifact is `thermal_gray`, a 16-bit image representing **Apparent Temperature**. 
- It is linear across the save window defined in `dataset_info.json`.
- **Conversion:** `T = T_min + DN * (T_max - T_min) / 65535`
- Note: This is *apparent* temperature, meaning emissivity is already applied via a Planck inversion integrated across the 8-14 µm band. A low-emissivity multi-layer insulation (MLI) blanket will realistically read much colder than its actual kinetic temperature.

> [!IMPORTANT]
> The `thermal_rgb` images are heavily tone-mapped derivatives meant for human visualization. **Machine learning models should train exclusively on the 16-bit `thermal_gray` data.**

---

## ⚠️ Known Limitations

For complete transparency regarding physical fidelity, please note:
1. **No Self-Viewing/Self-Occlusion Thermal Reflections:** A face reflects Earth and deep space, but not thermal radiation from other parts of the same spacecraft.
2. **No Conduction Gradients:** Components have uniform temperatures (plus minor per-face jitter). Real panels exhibit smooth thermal gradients.
3. **No Thermal Transients:** Temperatures are held at a steady state per frame.
4. **Earth Emission:** The Earth is treated as a perfect emitter (epsilon=1), which is a 1-2K approximation.

## 💻 Requirements
- **MATLAB R2026a** (or newer)
- **Toolboxes:** Image Processing Toolbox, Mapping Toolbox.
- **Network:** Active internet connection required for streaming live GeoGlobe basemaps.

---

## 🙌 Acknowledgments & Resources
- **Spacecraft 3D Models:** The 3D geometries used in this dataset are sourced from the [NASA 3D Resources Catalog](https://github.com/nasa/NASA-3D-Resources).
