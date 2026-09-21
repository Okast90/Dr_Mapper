# DJI Mapper

A modern mapping and waypoint mission planner for DJI drones.

<div>
<img src="https://github.com/user-attachments/assets/127ec817-1c62-4cfb-a5d2-a6c1801238a4" height="300px" />
<img src="https://github.com/user-attachments/assets/7ba5ac8f-bac7-4c4c-9671-a2c3f7f0207d" height="300px" />
<img src="https://github.com/user-attachments/assets/f94518bd-5776-42d5-9dc5-267a274b919b" height="250px" />
</div>

## Overview

DJI Mapper helps you define a survey area on a map (**surfacic 2D/3D grids**, **linear corridors**, or **direct GPX waypoint tracks**), generate optimized drone flight paths automatically, and export missions in formats compatible with DJI Fly, DJI Pilot 2 (KMZ/WPML) and Litchi (CSV).

The app is designed for rapid aerial mapping workflows: draw polygons, corridors or import GPX traces, refine contours, tune camera and geometric optimization settings, monitor real-time coverage percentage, inspect photo footprints for quality control, and export ready-to-use mission files.

## Features

- **Cross-platform support**: Runs on Windows, Linux, macOS, Android and the Web.
- **3 Dedicated Mapping & Mission Modes**:
  - **Grid Mode (Area)**: Surface photogrammetry for parcels, fields, rooftops, and buildings with boustrophedon sweep and crosshatch grid.
  - **Corridor Mode (Linear)**: Dedicated workflow for linear structures (roads, power lines, pipelines, rivers, fences) with adjustable buffer width (10 to 1,000 m) and 1 to 5 flight passes.
  - **Waypoint Mode (Direct GPX / Trace)**: Follow imported GPS waypoints, tracks, or custom flight paths sequentially with customizable speed, altitude, gimbal pitch, and photo triggers.
- **Comprehensive GPX & KML Import**:
  - Drag & Drop or file picker for `.gpx` and `.kml` files.
  - Supports GPX tracks (`<trk>`), routes (`<rte>`), and standalone waypoints (`<wpt>`).
  - Interactive import dialog allowing track selection and one-click flight mode conversion.
- **Direct on-map drawing & editing**: Create polygons, centerline polylines, or waypoints directly on the map, move vertices, delete individual points, straighten contours, or convert to 90° orthogonal geometry.
- **Coverage Quality Control (Photo Footprints & Shadows)**:
  - Ground footprint projection of each photograph based on sensor size, focal length, altitude and flight orientation.
  - Translucent shadow stacking to immediately identify coverage gaps and holes.
  - Dedicated **Radar button** in the floating map toolbar to toggle QC visualization.
- **Live Coverage Percentage Indicator**: Dynamic pill badge next to the search bar displaying the exact percentage of the survey area covered in real time (with color-coded quality assessment).
- **Advanced Geometric Optimization**:
  - **Optimal Sweep Angle (Auto)**: Evaluates flight orientations to minimize turns, battery consumption, and dead segments.
  - **Adaptive Margin Inset Buffer**: Keeps camera centers within boundaries while ensuring photo footprints cover exterior borders.
  - **Convex Partitioning (Ear-Clipping & Hertel-Mehlhorn)**: Decomposes complex or concave polygons (L, U, or star shapes) into convex sub-zones, eliminating coverage holes in interior corners.
  - **Residual Gap Fill**: Detects and covers residual unmapped gaps.
- **Multiple Map Layers**: Google Plans (Streets), Google Satellite (Hybrid), and OpenStreetMap (OSM) with dark mode auto-styling.
- **Full DJI & Litchi Export**:
  - **DJI Fly / DJI Pilot 2**: Complete `.kmz` archive with `template.kml` and `waylines.wpml`.
  - **Litchi**: `.csv` waypoint missions.
  - **KML**: Import and export of boundary polygons and linear routes.
- **Live Weather & GPS**: Real-time wind speed, temperature via Open-Meteo, and GPS satellite status in the top bar.

## How it works

1. Select your **Survey Mode** (Grid for areas or Corridor for linear paths).
2. Draw the area or centerline directly on the map.
3. Validate and refine geometry with editing and alignment tools if needed.
4. Configure flight altitude, speed, overlap, camera presets, and geometric optimization (`Convex Split`, `Border Margin`).
5. Inspect real-time **Coverage Percentage** and toggle the **Radar QC Overlay** to check for coverage gaps.
6. Export the mission to DJI Fly/Pilot 2 (KMZ/WPML), Litchi (CSV), or KML.
7. Load onto your drone controller and start the automated survey flight.

This workflow keeps the process fast and intuitive while still giving you enough control over the final geometry and flight plan.

## Supported Aircraft

- **[DJI Fly](https://www.dji.com/downloads/djiapp/dji-fly)**: DJI Mini 4 Pro, DJI Mini 5 Pro, DJI Air 3, DJI Air 3S, DJI Mavic 3 (Regular/Cine/Classic), DJI Mavic 4 Pro
- **[Litchi](https://flylitchi.com)**: Mini 2, Mini SE (NOT Mini 4K), Air 2S, Mavic Mini 1, Mavic Air 2, Mavic 2 Zoom/Pro, Mavic Air 1, Mavic Pro 1, Phantom 4 (Standard/Advanced/Pro/ProV2), Phantom 3 (Standard/4K/Advanced/Professional), Inspire 1 (X3/Z3/Pro/RAW), Inspire 2 and Spark
- **[Litchi Pilot (beta)](https://forum.flylitchi.com/t/open-beta-litchi-pilot/10621)**: Mini 3, Mini 3 Pro, Mavic 3E, Mavic 3T, Matrice 4, Matrice 30, Matrice 300 & 350 RTK, Matrice 400

**IMPORTANT NOTE regarding Litchi Pilot**: I haven't tested how well Litchi Pilot plays with DJI-Mapper, so I can't guarantee a smooth experience.

## Installation

1. Download the latest version from the [Releases](https://github.com/YarosMallorca/DJI-Mapper/releases/latest) page.

2. Unzip the downloaded file and run the executable. On Linux run `DJI-Mapper` from the terminal.

3. If you're on Windows and you get a warning from Windows Defender, click on "More info" and then "Run anyway".

## Usage

1. Open the map and switch to the contour drawing mode.
2. Draw the area to survey directly on the map by adding points around the perimeter.
3. Validate the contour, then fine-tune it with the editing tools if needed.
4. Adjust the aircraft and camera parameters according to your needs.
5. Review the generated mission preview and flight lines on the map.
6. Export the mission to DJI Fly or Litchi, or export the polygon to KML.
7. Load the mission on your drone and start the flight.

### Polygon workflow

- The app accepts a contour drawn directly in the map interface.
- A polygon with at least 3 points is immediately usable as a mission boundary.
- You can move vertices, delete selected points, straighten the contour, or convert it to 90° corners.
- Imported KML polygons and on-map polygons use the same workflow.

_Note: Do not modify or save the mission from inside DJI Fly if the app requires straight curves, because the native DJI editor may break the planned path geometry._

## Why it is useful

DJI Mapper is useful for survey, inspection, and photogrammetry missions where you need a reliable boundary definition and a clean flight plan without spending time manually building the route by hand.

It is especially well suited to projects where you want:

- a fast map-based mission setup
- quick contour adjustments
- repeatable export for DJI and Litchi workflows
- a clear path from area definition to final mission file

## Contributing

Contributions are most welcome! If you have any ideas, suggestions, or issues, please open an issue or a pull request.

## Building from source

**Requirements:**

- Dart SDK
- Flutter SDK

1. Clone the repository.
2. Run `flutter pub get` to install the dependencies.
3. Run `flutter build <platform>` to build the app for your platform or `flutter run` to run it on your device.
4. Run `flutter build <platform> --release` to build the release version.

- Recommend using VSCode with the Flutter extension for development, it will allow Hot-Reload and other features.

## Docker (Web)

Build and run using Docker (multi-stage build - no Flutter required):

```bash
# Build and run with Docker Compose
docker-compose up -d --build

# Or build manually with Docker
docker build -t dji-mapper:latest .
docker run -d -p 8090:80 --name dji-mapper dji-mapper:latest
```

Stop with:

```bash
docker-compose down
```

Access at http://localhost:8090

**Production deployment** (dji.sartrainer.org):
```bash
# Use production docker-compose (container listens on port 8090)
docker-compose -f docker-compose.prod.yml up -d --build
```

**Caddy configuration** (running on host):
```
dji.sartrainer.org {
    reverse_proxy localhost:8090
}
```

**Note**: First build takes 5-10 minutes (downloads Flutter SDK). Subsequent builds are faster with layer caching.

### Production Deployment Steps

**1. Build the Docker image locally:**
```bash
docker build -t dji-mapper:latest .
```

**2. Transfer the image to the production server:**
```bash
# Option A: Save and transfer via SCP
docker save dji-mapper:latest | gzip > dji-mapper.tar.gz
scp dji-mapper.tar.gz user@your-server:/path/to/deploy/

# Option B: Push to a registry (Docker Hub, GitHub, etc.)
docker tag dji-mapper:latest your-registry/dji-mapper:latest
docker push your-registry/dji-mapper:latest
```

**3. On the production server, load and run:**
```bash
# If using image transfer
gunzip < dji-mapper.tar.gz | docker load

# If using registry
docker pull your-registry/dji-mapper:latest

# Copy docker-compose.prod.yml to server, then start
docker-compose -f docker-compose.prod.yml up -d

# Verify it's running
docker ps
docker logs -f dji-mapper
```

**4. Configure Caddy reverse proxy:**
```bash
# Edit Caddyfile
sudo nano /etc/caddy/Caddyfile

# Add this block:
dji.sartrainer.org {
    reverse_proxy localhost:8090
}

# Restart Caddy
sudo systemctl reload caddy
```

**5. Verify deployment:**
```bash
# Check container health
curl http://localhost:8090

# Check from external
curl https://dji.sartrainer.org
```
#   D r _ M a p p e r  
 