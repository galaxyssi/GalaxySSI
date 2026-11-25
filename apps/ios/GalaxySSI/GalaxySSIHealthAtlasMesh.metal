#include <metal_stdlib>
using namespace metal;

struct AtlasMeshVertex { float2 position; float2 uv; };
struct AtlasMeshOutput { float4 position [[position]]; float2 uv; };

vertex AtlasMeshOutput galaxyssiAtlasMeshVertex(uint index [[vertex_id]], device const AtlasMeshVertex *vertices [[buffer(0)]]) {
    AtlasMeshOutput output;
    output.position = float4(vertices[index].position, 0.0, 1.0);
    output.uv = vertices[index].uv;
    return output;
}

fragment half4 galaxyssiAtlasMeshFragment(AtlasMeshOutput input [[stage_in]], texture2d<half> image [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return image.sample(linearSampler, input.uv);
}
