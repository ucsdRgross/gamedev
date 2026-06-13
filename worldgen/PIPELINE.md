# Weighted Momentum Procedural Generation Pipeline

This document describes the GPU-accelerated world generation engine utilizing weighted force vectors and Perlin-guided valleys.

## ??? The Core Workflow
The engine shifts from passive downhill drainage to a dynamic system of competing physical forces. It utilizes two distinct climate maps:
1. Rainfall Noise: Determines starting weights and erosion power (carves the landscape).
2. Humidity Noise: Determines final water fill state (renders the river).

## ??? Step-by-Step Implementation

### Step 1: Base Structure & Valley Blueprint
Base Heightmap: Generated via layered Simplex/Perlin noise to establish continental mass.
River Valley Noise: A low-frequency ridge-noise map that creates infinite, twisting guide lines.

### Step 2: Direction Map (Local Gradients)
The GPU calculates the 2D gradient for every pixel based on the Base Heightmap. Each pixel points toward its lowest immediate neighbor.

### Step 3: Weighted Momentum Iteration (The Force Pass)
Every pixel is assigned a weight. Pixels overlapping the Valley Blueprint receive a weight boost. In a cellular-automata pass, high-weight neighbors can overwrite the gradient direction of low-weight pixels.

### Step 4: Shape Warping (Organic Meandering)
A distortion noise offsets the vector coordinates, creating natural curves and meanders in the force channels.

### Step 5: Heightmap Carving (Groove Cutting)
Final high-weight channels subtract height from the base terrain, physically cutting grooves and canyons.

### Step 6: Climate Overlay (Late Hydrology Fill)
Humidity Noise is checked. If the area is Wet, the groove is filled with water. If Dry, it remains an empty canyon.
