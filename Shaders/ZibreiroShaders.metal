#include <metal_stdlib>
using namespace metal;

struct ZibreiroUniforms {
    float4 resolutionAndTime;
    float4 placement;
    float4 widthsAndTopHeight;
    float4 heightsAndMaterial;
    float4 surface;
    float4 baseDark;
    float4 deepRed;
    float4 ember;
    float4 ochre;
    float4 bruised;
    float4 smokeGold;
};

struct Raster { float4 position [[position]]; float2 uv; };

vertex Raster fullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    Raster out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

#ifndef ZIBREIRO_ALGORITHM_VERSION
#define ZIBREIRO_ALGORITHM_VERSION 1
#endif

#if ZIBREIRO_ALGORITHM_VERSION == 1
#include "Algorithms/001-webgl-srgb-dither.metalinc"
#elif ZIBREIRO_ALGORITHM_VERSION == 2
#include "Algorithms/002-shadow-range.metalinc"
#elif ZIBREIRO_ALGORITHM_VERSION == 3
#include "Algorithms/003-six-bit-display-dither.metalinc"
#elif ZIBREIRO_ALGORITHM_VERSION == 4
#include "Algorithms/004-blue-noise-texture.metalinc"
#elif ZIBREIRO_ALGORITHM_VERSION == 5
#include "Algorithms/005-four-code-blue-noise.metalinc"
#elif ZIBREIRO_ALGORITHM_VERSION == 6
#include "Algorithms/006-protected-black.metalinc"
#else
#error Unsupported ZIBREIRO_ALGORITHM_VERSION
#endif
