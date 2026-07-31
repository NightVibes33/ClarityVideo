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

struct TileBlendUniforms {
    uint originX;
    uint originY;
    uint overlapX;
    uint overlapY;
    uint leftBoundary;
    uint rightBoundary;
    uint topBoundary;
    uint bottomBoundary;
};

kernel void blendOverlappingTile(
    texture2d<half, access::read> tile [[texture(0)]],
    texture2d<half, access::read_write> canvas [[texture(1)]],
    constant TileBlendUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= tile.get_width() || gid.y >= tile.get_height()) return;
    uint2 outputPosition = uint2(u.originX, u.originY) + gid;
    if (outputPosition.x >= canvas.get_width() || outputPosition.y >= canvas.get_height()) return;

    float weight = 1.0;
    if (u.leftBoundary == 0 && u.overlapX > 0 && gid.x < u.overlapX) {
        float t = float(gid.x) / float(u.overlapX);
        weight *= 0.5 - 0.5 * cos(M_PI_F * t);
    }
    if (u.rightBoundary == 0 && u.overlapX > 0 && gid.x + u.overlapX >= tile.get_width()) {
        float t = float(tile.get_width() - 1 - gid.x) / float(u.overlapX);
        weight *= 0.5 - 0.5 * cos(M_PI_F * max(0.0, t));
    }
    if (u.topBoundary == 0 && u.overlapY > 0 && gid.y < u.overlapY) {
        float t = float(gid.y) / float(u.overlapY);
        weight *= 0.5 - 0.5 * cos(M_PI_F * t);
    }
    if (u.bottomBoundary == 0 && u.overlapY > 0 && gid.y + u.overlapY >= tile.get_height()) {
        float t = float(tile.get_height() - 1 - gid.y) / float(u.overlapY);
        weight *= 0.5 - 0.5 * cos(M_PI_F * max(0.0, t));
    }

    float4 incoming = float4(tile.read(gid));
    float4 existing = float4(canvas.read(outputPosition));
    float existingWeight = existing.a;
    float total = existingWeight + weight;
    float3 color = total > 0.0
        ? (existing.rgb * existingWeight + incoming.rgb * weight) / total
        : incoming.rgb;
    canvas.write(half4(half3(color), half(min(1.0, total))), outputPosition);
}
