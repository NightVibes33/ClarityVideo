#include <metal_stdlib>
using namespace metal;
kernel void lanczosPlaceholder(texture2d<float, access::read> source [[texture(0)]],
                               texture2d<float, access::write> target [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;
    float2 uv = (float2(gid) + 0.5) / float2(target.get_width(), target.get_height());
    uint2 p = uint2(uv * float2(source.get_width(), source.get_height()));
    target.write(source.read(min(p, uint2(source.get_width()-1, source.get_height()-1))), gid);
}
