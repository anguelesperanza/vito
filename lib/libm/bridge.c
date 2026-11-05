// ABI bridge for libm.
//
// Odin emits calls like sinf(x) with the float in r0 (soft-float convention).
// VitaSDK's newlib libm is hard-float: it reads x from s0 and returns in s0.
// Without this bridge those calls silently return garbage.
//
// Each vito_* function takes and returns the raw bits in integer registers
// and calls the real libm function. The build renames the symbols inside
// Odin's object only (objcopy --redefine-syms=redefine.syms), so vita2d and
// newlib themselves keep calling the real functions.
//
// To cover another libm function: add it below and to redefine.syms.

#include <math.h>
#include "../bridge_utils.h"

static inline double   u2d(uint64_t v) { double   d; memcpy(&d, &v, sizeof d); return d; }
static inline uint64_t d2u(double   d) { uint64_t v; memcpy(&v, &d, sizeof v); return v; }

#define F1(fn)  uint32_t vito_##fn##f(uint32_t a) { return f2u(fn##f(u2f(a))); }
#define F2(fn)  uint32_t vito_##fn##f(uint32_t a, uint32_t b) { return f2u(fn##f(u2f(a), u2f(b))); }
#define F3(fn)  uint32_t vito_##fn##f(uint32_t a, uint32_t b, uint32_t c) { return f2u(fn##f(u2f(a), u2f(b), u2f(c))); }
#define D1(fn)  uint64_t vito_##fn(uint64_t a) { return d2u(fn(u2d(a))); }
#define D2(fn)  uint64_t vito_##fn(uint64_t a, uint64_t b) { return d2u(fn(u2d(a), u2d(b))); }
#define D3(fn)  uint64_t vito_##fn(uint64_t a, uint64_t b, uint64_t c) { return d2u(fn(u2d(a), u2d(b), u2d(c))); }

#define ONE_ARG(X) \
    X(sin) X(cos) X(tan) X(asin) X(acos) X(atan) X(sinh) X(cosh) X(tanh) \
    X(exp) X(exp2) X(log) X(log2) X(log10) X(sqrt) X(cbrt) \
    X(floor) X(ceil) X(trunc) X(round) X(fabs)
#define TWO_ARG(X)   X(atan2) X(pow) X(fmod) X(fmin) X(fmax) X(hypot) X(copysign)
#define THREE_ARG(X) X(fma)

ONE_ARG(F1)
TWO_ARG(F2)
THREE_ARG(F3)
ONE_ARG(D1)
TWO_ARG(D2)
THREE_ARG(D3)
