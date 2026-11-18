# Mataki Drone AI — Version 0.1

Early local prototype for processing DJI Mavic 2 Pro warehouse inspection footage.

## What this prototype does

- Accepts an MP4 video upload.
- Reads video metadata (duration, frame rate and resolution).
- Extracts still frames at a user-selected time interval.
- Displays extracted frames for visual review.
- Packages the extracted images and a metadata file into a ZIP download.

## What it does not do yet

This is the first data-ingestion milestone. It does **not** yet identify pallet-racking components, detect damage, reconstruct 3D geometry, or produce compliance measurements. Those capabilities require a labelled Mataki image dataset, model evaluation and a calibrated measurement workflow.

## Run locally

Python 3.10–3.12 is recommended.

### Windows

1. Install Python from https://www.python.org/downloads/ and enable **Add Python to PATH**.
2. Download or clone this repository and open a terminal in the `drone-ai` folder.
3. Create a virtual environment:

   ```powershell
   py -m venv .venv
   .venv\Scripts\Activate.ps1
   ```

4. Install dependencies:

   ```powershell
   python -m pip install --upgrade pip
   pip install -r requirements.txt
   ```

5. Start the app:

   ```powershell
   streamlit run app.py
   ```

### macOS

1. Install Python 3.10–3.12.
2. Open Terminal in the `drone-ai` folder.
3. Create and activate a virtual environment:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install --upgrade pip
   pip install -r requirements.txt
   streamlit run app.py
   ```

The app opens in your browser, usually at http://localhost:8501.

## First test footage guidance

For the first trial, capture one aisle with:
- A slow, steady flight and minimal yaw/roll changes.
- The camera aimed squarely towards the rack faces where practical.
- Good, even lighting and minimal motion blur.
- A view that includes the full height of the rack, including floor and top beam.
- A short test clip (30–60 seconds) before recording a whole warehouse.

Keep the original video file. Do not rely on this prototype's extracted frames as the only inspection record.

## Data handling

This prototype is intended to run locally on the laptop. Uploaded footage is processed by the running app and temporary files are removed when processing finishes or the session ends. Do not deploy it publicly or upload customer footage to a third-party service until Mataki has approved the hosting, access-control and retention arrangements.

## Measurement and safety limitation

Any future AI-generated damage flags or measurements must be treated as preliminary findings until validated against independent physical measurements and reviewed by a competent inspector. This prototype does not establish AS/NZS 4084:2023 compliance.
