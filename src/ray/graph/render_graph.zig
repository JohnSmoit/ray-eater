//! Declaratively specifies rendering (graphics, compute, and the like)
//! pipelines, and handles creation of renderpasses for all unique rendering pipelines
//! before exposing their functionality to a rendering queue.

const std = @import("std");

// A series of passes arranged into a graph whose edges are 
// attachment and synchronization dependencies

// Each pass may specify a series of input and output resources
// with some sort of unique identifier (most likely a hash based on a human readble string)
// Multiple passes may associate with the same resource so long as the graph remains acyclic,
// and the specified attachments are valid for the given pass.
// Other then this, simply specifying resources and attachments should be enough for the graph
// to bake and resolve into a (sort of) optimized set of renderpasses for every operation my rendering driver
// might need.
//
// Inputs/outputs can be:
// - Images of any variety
//      - G-buffer attachments
//      - Samplers
// - Storage Buffers
//
// Likely easier and requiring less syncrhonization are:
// - Uniform buffers
// - Push Constants
//
// Generally, there are 2 types of pass we need to consider:
// - Renderpasses (for standard graphics pipelines)
//  - These will assemble VkPipelines configured for graphics render passes
// - Compute Passes (for more exotic SDF-traced specific pipelines)
//  - These will assemble VkComputePipelines (might be the same handle type i forgor)
//
//  Might be too much for now, but I also want to keep vulkan-specific handles out of the render graph until
//  a special "resolution phase" which takes platform independent baked passes and creates the appropriate
//  API types for whichever graphics API is being used...


