from __future__ import annotations

import io
import json
import zipfile
from datetime import datetime, timezone

import cv2
import streamlit as st
from PIL import Image

st.set_page_config(
    page_title="Mataki Drone AI | v0.1",
    page_icon="🛠️",
    layout="wide",
)

st.title("Mataki Drone AI")
st.caption("Version 0.1 · Drone footage ingestion and frame extraction")
st.info(
    "Prototype milestone 1: upload a drone video, inspect its properties, "
    "extract still frames and download them for review. AI component recognition "
    "and calibrated measurements are not enabled yet."
)

with st.sidebar:
    st.header("Extraction settings")
    interval_seconds = st.number_input(
        "Extract one frame every (seconds)",
        min_value=0.5,
        max_value=30.0,
        value=2.0,
        step=0.5,
    )
    max_frames = st.slider(
        "Maximum frames to extract",
        min_value=10,
        max_value=300,
        value=120,
        step=10,
    )
    st.caption("For an initial test, use a 30–60 second clip and a 2-second interval.")

uploaded = st.file_uploader(
    "Upload DJI Mavic 2 Pro footage",
    type=["mp4", "mov", "avi", "m4v"],
    help="The file is processed by this local app. Keep your original video unchanged.",
)

def extract_frames(video_bytes: bytes, interval: float, limit: int):
    import tempfile
    from pathlib import Path

    temp_path = None
    cap = None
    frames = []
    metadata = {}

    try:
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_file:
            temp_file.write(video_bytes)
            temp_path = Path(temp_file.name)

        cap = cv2.VideoCapture(str(temp_path))
        if not cap.isOpened():
            raise ValueError(
                "OpenCV could not open this video. Try exporting it as a standard MP4 (H.264)."
            )

        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0)
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        duration = frame_count / fps if fps > 0 else 0

        metadata = {
            "filename": uploaded.name if uploaded else "video",
            "frames_per_second": round(fps, 3),
            "source_frame_count": frame_count,
            "width_pixels": width,
            "height_pixels": height,
            "duration_seconds": round(duration, 2),
            "extraction_interval_seconds": interval,
            "extracted_at_utc": datetime.now(timezone.utc).isoformat(),
            "prototype": "Mataki Drone AI v0.1",
        }

        step = max(1, int(round(fps * interval))) if fps > 0 else 1
        frame_index = 0
        while len(frames) < limit:
            ok, frame = cap.read()
            if not ok:
                break

            if frame_index % step == 0:
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                timestamp = frame_index / fps if fps > 0 else 0
                frames.append(
                    {
                        "number": len(frames) + 1,
                        "source_frame": frame_index,
                        "timestamp_seconds": round(timestamp, 3),
                        "image": Image.fromarray(rgb),
                    }
                )
            frame_index += 1

        return metadata, frames
    finally:
        if cap is not None:
            cap.release()
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass

if uploaded:
    file_bytes = uploaded.getvalue()
    st.write(f"**File:** {uploaded.name} · **Size:** {len(file_bytes) / (1024 * 1024):.1f} MB")

    if st.button("Analyse video and extract frames", type="primary"):
        with st.spinner("Reading video and extracting frames…"):
            try:
                metadata, frames = extract_frames(file_bytes, interval_seconds, max_frames)
                st.session_state["drone_ai_metadata"] = metadata
                st.session_state["drone_ai_frames"] = frames
            except Exception as exc:
                st.error(f"Could not process this video: {exc}")

metadata = st.session_state.get("drone_ai_metadata")
frames = st.session_state.get("drone_ai_frames")

if metadata and frames:
    st.subheader("Video properties")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Duration", f"{metadata['duration_seconds']:.1f} sec")
    c2.metric("Frame rate", f"{metadata['frames_per_second']:.1f} fps")
    c3.metric("Resolution", f"{metadata['width_pixels']} × {metadata['height_pixels']}")
    c4.metric("Frames extracted", str(len(frames)))

    st.subheader("Extracted frames")
    st.caption("Review these images for focus, lighting, motion blur and coverage of the rack.")
    cols = st.columns(3)
    for idx, item in enumerate(frames):
        with cols[idx % 3]:
            st.image(
                item["image"],
                caption=f"Frame {item['number']} · {item['timestamp_seconds']:.1f} sec",
                use_container_width=True,
            )

    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("video_metadata.json", json.dumps(metadata, indent=2))
        for item in frames:
            image_buffer = io.BytesIO()
            item["image"].save(image_buffer, format="JPEG", quality=92)
            filename = f"frames/frame_{item['number']:04d}_{item['timestamp_seconds']:.1f}s.jpg"
            zf.writestr(filename, image_buffer.getvalue())

    st.download_button(
        "Download extracted frames and metadata (ZIP)",
        data=archive.getvalue(),
        file_name="mataki_drone_ai_v01_frames.zip",
        mime="application/zip",
        type="primary",
    )
else:
    st.subheader("Ready for your first test flight")
    st.markdown(
        """
        1. Capture a short, steady pass along one pallet-racking aisle.
        2. Upload the original video above.
        3. Extract frames and review the images.
        4. Download the ZIP and keep it with the original source video.
        """
    )

st.divider()
st.caption(
    "Mataki Drone AI v0.1 is an experimental data-ingestion tool. "
    "It does not identify defects, calculate certified dimensions or determine compliance."
)
