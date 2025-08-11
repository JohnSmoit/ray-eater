//! Takes in a fixed, preallocated 
//! buffer of memory and manages it as a pool of 
//! a given type of objects to be allocated and freed independently.
//!
//! Free space will be tracked as a RB tree (or maybe a buddy allocator dunno)
//! and alignment requirements and backing allocators (to create the buffer) can be specified at 
//! initialization time...
//!
//! Pools contain a fixed capacity that CANNOT be modified unless the pool is later resized,
//! which will probably have a buch of bad side effects that make it not really that good of an idea
//! (i.e invalidates everything so all pointers to handles are not guaranteed).


