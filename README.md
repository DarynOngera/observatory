# Multimedia Systems Observatory

## Overview

This project builds an interactive multimedia systems observatory that unifies media structure analysis (ffprobe), media transformation observation (ffmpeg via Membrane orchestration), GOP and frame-level behavior, and perceptual verification via a media player. The system treats FFmpeg tools as observable processes rather than black-box commands, focusing on making codec decisions, container effects, and timing behavior explainable through structured metadata, process events, GOP statistics, and synchronized visual playback, all managed in Elixir with Membrane pipelines.

The observatory is designed for educational and research purposes, emphasizing conceptual clarity on how codecs, containers, and media pipelines work. It exposes observable behaviors without reimplementing codec logic, allowing users to inspect, compare, and understand media systems through an interactive interface.

## Key Objectives

- **Observability**: Make internal media behaviors (e.g., timing, synchronization, encoding tradeoffs) inspectable and explainable.
- **Comparability**: Enable side-by-side analysis of media transformations and their perceptual impacts.
- **Educational Focus**: Provide mental models and real-world insights into multimedia systems, tied to practical observations.

## System Pillars

The project is structured around three interconnected pillars, orchestrated by Membrane in Elixir:

1. **Structure (ffprobe Integration)**:
   - Analyzes container metadata, stream details, timing, timebases, codec identities, durations, and bitrates.
   - Outputs a normalized Media Schema for consistent introspection.

2. **Transformation (ffmpeg via Membrane)**:
   - Performs transcoding, re-muxing, filtering, and parameter variations (e.g., CRF, presets, GOP sizes).
   - Observes progress, encoding speed, bitrate evolution, frame decisions, and warnings/errors.
   - Generates a structured Process Schema and event timelines.

3. **Perception (Media Player in Phoenix LiveView)**:
   - Provides playback for input and output media with accurate seeking and scrubbing.
   - Supports A/B comparisons and sync verification.
   - Overlays timelines with GOP boundaries, keyframes, and encode phases for explanatory cues (e.g., "This seek snapped to a keyframe").

Additionally, **GOP & Frame-Level Analysis** is a first-class feature:
   - Computes GOP sizes, keyframe intervals, I/P/B distributions, and timestamps.
   - Ties statistics to seek accuracy, compression efficiency, and playback behavior using ffprobe and encoder logs.

## Architecture

- **Backend**: Elixir with Membrane for pipeline orchestration and observation.
- **Frontend**: Phoenix LiveView for interactive visualizations and the embedded media player.
- **Tools**:
  - ffprobe: For media introspection and GOP/frame stats.
  - ffmpeg: For transformations, wrapped in Membrane bins.
- **Data Flow**:
  ```
  Upload Media → Membrane Pipeline → ffprobe (Schema & GOP Stats) → ffmpeg (Process Events) → Output Media → Player (Verification with Overlays)
  ```
  Membrane ensures backpressure handling, telemetry, and event correlation across stages.

## Features

- **Media Upload and Inspection**: Upload files for immediate structure analysis.
- **GOP Visualization**: Timelines showing frame distributions and their impact on seeking.
- **Transformation Experiments**: Run encodes with variable parameters and observe real-time metrics.
- **Perceptual Playback**: Embedded player with explanatory overlays for A/B comparisons.
- **Explanations and Insights**: Tie observations to system behaviors (e.g., why sync breaks or quality varies).

Phased Implementation:
- Phase 1: Structure analysis.
- Phase 2: GOP awareness.
- Phase 3: Transformations.
- Phase 4: Perceptual layer.

## Non-Goals

- No custom codec implementation.
- No GPU acceleration or production-scale streaming.
- No advanced editing (e.g., color grading, NLE features).
- No pixel-domain analysis in v1.

## Installation

### Prerequisites
- Elixir 1.14+ and Erlang/OTP 25+.
- Phoenix 1.7+.
- FFmpeg and ffprobe installed (version 5.0+ recommended).
- Membrane Framework and dependencies.

### Setup
1. Clone the repository:
   ```
   git clone https://github.com/yourusername/multimedia-systems-observatory.git
   cd multimedia-systems-observatory
   ```
2. Install dependencies:
   ```
   mix deps.get
   ```
3. Set up the database (if using persistence, optional for v1):
   ```
   mix ecto.setup
   ```
4. Start the Phoenix server:
   ```
   mix phx.server
   ```
   Or for interactive development: `iex -S mix phx.server`.

## Usage

1. Access the web interface at `http://localhost:4000`.
2. Upload a media file (e.g., MP4, WebM).
3. View introspection results (structure schema).
4. Analyze GOP stats and timelines.
5. Configure and run transformations (e.g., change codec or GOP size).
6. Compare input/output in the player with overlays for insights.

Example Workflow:
- Upload a video → Inspect container and streams → Adjust encode preset → Observe process events → Play both versions with GOP markers.

