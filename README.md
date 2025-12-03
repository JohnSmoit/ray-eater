# RayEater
[![Ray Eater CI](https://github.com/JohnSmoit/RayEater/actions/workflows/ci.yaml/badge.svg)](https://github.com/JohnSmoit/RayEater/actions/workflows/ci.yaml)

Welcome to the public view of the ray-eater renderer's repository.

## Overview
Ray Eater (working title) intends to be a unified renderer that provides integrations and streamlines usage for rendering applications involving more modern graphics pipelines, such as the excellent [3D Gaussian Splatting](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/3d_gaussian_splatting_high.pdf).

## What's here?
Ray eater is still in heavy development, with only the vulkan implementation of the  RHI (rendering hardware interface) being done at the moment. A lot of work is being done behind the scenes to integrate a Gaussian Splat renderer along with the foundational work to create a working asset toolchain that supports the diverse formats of assets required by these sorts of rendering pipelines.

## Supported Platforms
* Windows -- Supported

Linux is very close to being supported, but there are still some issues with making the windowing cross platform enough to where the swapchain presents to it without issue

## Setup
### Prerequisites
ray eater is light on preexisting dependencies, but vulkan drivers compatible with API version 1.3.* must be preinstalled, along with a version of the zig compiler >= 0.15.0.

### Getting The Source
to install ray eater on your system simply checkout the repository

#### HTTPS
```bash
git clone https://github.com/JohnSmoit/ray-eater.git 
```

#### SSH
```bash
git clone git@github.com:JohnSmoit/ray-eater.git
```

### Building and running
ray eater makes use of the [zig build system](https://ziglang.org/learn/build-system/)
and provides several samples and unit tests to get an idea of what the current capabilities of the project are.

```bash
zig build run-[sample_name] --  [cmd-args]*
```

run 
```
zig build help
```
to see available samples, along with descriptions.
