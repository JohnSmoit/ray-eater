#ifndef RAY_ALLOC_INTERFACE_H
#define RAY_ALLOC_INTERFACE_H

#include "types.h"

typedef void* (*ray_alloc_fcn)(void * state, usize bytes);
typedef void* (*ray_realloc_fcn)(void * state, void * orig, usize bytes);
typedef void (*ray_free_fcn)(void * state, void * data);

// constexpr detection ????
// #define ICE_P(x) (sizeof(int) == sizeof(*(1 ? ((void*)((x) * 0l)) : (int*)1)))


// void dum(int b) {
//     ICE_P(100 + 1); // this is true
// 
//     int a = b + 1;
// 
//     ICE_P(a); //... and this is false
// }
// basically a vtable, (but hopefully monomorphic if I can help it)
typedef struct ray_allocator_interface {
    ray_alloc_fcn allocate;
    ray_realloc_fcn reallocate;
    ray_free_fcn free;
} ray_allocator_interface;

// template struct for generic allocator
typedef struct ray_gen_allocator {
    ray_allocator_interface interface;
} ray_gen_allocator;

// this is what I'd like to avoid usage wise:
// but I don't think its possible to avoid this sort of runtime 
// function binding in c...
//
/**
 * some_allocator a = {
 *      .interface = {
 *          .allocate = some_allocate_func,
 *          .reallocate = some_realloc_func,
 *          .free = some_free_func
 *      },
 *      .other_state = // Init other state here //;
 *  }
 * */

// this is bad:
// alloc->interface->allocate(alloc->state, 100000)


// so this instead:
// ray_alloc(alloc, 100000)
// basic allocator utility functions

void * ray_alloc(ray_gen_allocator * allocator, usize bytes);
void * ray_realloc(ray_gen_allocator * allocator, void * orig, usize bytes);
void ray_free(ray_gen_allocator * allocator, void * data);

// vcouple of helper macros

#define ray_alloc_t(allocator, type)                \
    (type *) ray_alloc(allocator, sizeof(type))

#define ray_nfree(allocator, data)                  \
    ray_free(allocator, *data)                      \
    *data = NULL

#endif
