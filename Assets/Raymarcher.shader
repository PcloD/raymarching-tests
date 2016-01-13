Shader "Raymarcher" {
  Properties {
    _sun ("Sun", Vector) = (0, 0, 0, 0)
    _far ("Far Depth Value", Float) = 20
    _edgeFuzz ("Edge fuzziness", Range(1, 20)) = 1.0
    _lightStep ("Light step", Range(0.1, 5)) = 1.0
    _step ("Raycast step", Range(0.1, 5)) = 1.0
    _dark ("Dark value", Color) = (0, 0, 0, 0)
    _light ("Light Value", Color) = (1, 1, 1, 1)
    [Toggle] _debugDepth ("Display depth field", Float) = 0
    [Toggle] _debugLight ("Display light field", Float) = 0
  }
  SubShader {
    Tags {"Queue"="Background+1" "IgnoreProjector"="True" "RenderType"="Transparent"}
    Blend SrcAlpha OneMinusSrcAlpha
    ZWrite On
    ZTest Off
    Pass {
      CGPROGRAM

      #pragma vertex vert
      #pragma fragment frag
      #pragma target 3.0

      #include "UnityCG.cginc"
      #include "UnityLightingCommon.cginc" // for _LightColor0
      #define IF(a, b, c) lerp(b, c, step((fixed) (a), 0));

      uniform float _far;
      uniform float _lightStep;
      uniform float3 _sun;
      uniform float4 _light;
      uniform float4 _dark;
      uniform float _debugDepth;
      uniform float _debugLight;
      uniform float _edgeFuzz;
      uniform float _step;

      /**
       * Sphere at origin c, size s
       * @param center_ The center of the sphere
       * @param radius_ The radius of the sphere
       * @param point_ The point to check
       */
      float geom_soft_sphere(float3 center_, float radius_, float3 point_) {
        float rtn = distance(center_, point_);
        return IF(rtn < radius_, (radius_ - rtn) / radius_ / _edgeFuzz, 0);
      }

      /**
       * A rectoid centered at center_
       * @param center_ The center of the cube
       * @param halfsize_ The halfsize of the cube in each direction
       */
      float geom_rectoid(float3 center_, float3 halfsize_, float3 point_) {
        float rtn = IF((point_[0] < (center_[0] - halfsize_[0])) || (point_[0] > (center_[0] + halfsize_[0])), 0, 1);
        rtn = rtn * IF((point_[1] < (center_[1] - halfsize_[1])) || (point_[1] > (center_[1] + halfsize_[1])), 0, 1);
        rtn = rtn * IF((point_[2] < (center_[2] - halfsize_[2])) || (point_[2] > (center_[2] + halfsize_[2])), 0, 1);
        rtn = rtn * distance(point_, center_);
        float radius = length(halfsize_);
        return IF(rtn > 0, (radius - rtn) / radius / _edgeFuzz, 0);
      }

      /**
       * Calculate procedural geometry.
       * Return (0, 0, 0) for empty space.
       * @param point_ A float3; return the density of the solid at p.
       * @return The density of the procedural geometry of p.
       */
      float march_geometry(float3 point_) {
        return
          geom_rectoid(float3(0, 0, 0), float3(7, 7, 7), point_) +
          geom_soft_sphere(float3(10, 0, 0), 7, point_) +
          geom_soft_sphere(float3(-10, 0, 0), 7, point_) +
          geom_soft_sphere(float3(0, 0, 10), 7, point_) +
          geom_soft_sphere(float3(0, 0, -10), 7, point_);
      }

      /** Return a randomish value to sample step with */
      float rand(float3 seed) {
        return frac(sin(dot(seed.xyz ,float3(12.9898,78.233,45.5432))) * 43758.5453);
      }

      /**
       * March the point p along the cast path c, and return a float2
       * which is (density, depth); if the density is 0 no match was
       * found in the given depth domain.
       * @param point_ The origin point
       * @param cast_ The cast vector
       * @param max_ The maximum depth to step to
       * @param step_ The increment to step in
       * @return (denity, depth)
       */
      float march_raycast(inout float3 point_, float3 cast_, float max_, float step_) {
        float3 origin_ = point_;
        float depth_ = 0;
        float density_ = 0;
        int steps = floor(max_ / step_);
        for (int i = 0; (density_ <= 1) && (i < steps); ++i) {
          point_ = origin_ + cast_ * i * step_ + rand(point_) * cast_ * step_;
          density_ += march_geometry(point_);
        }
        density_ = IF(density_ > 1, 1, density_);
        return density_;
      }

      /**
       * Simple lighting; raycast from depth point to light source, and get density on path
       * @param point_ The surface world coordinate.
       * @param cast_ The original cast (ie. camera view direction)
       * @param raycast_ The result of the original raycast
       * @param max_ The max distance to cast
       * @param step_ The step increment
       */
      float march_lighting(float3 point_, float2 raycast_, float max_, float step_) {
        float3 lcast_ = normalize(_sun - point_);
        return march_raycast(point_, lcast_, max_, step_);
      }

      /**
       * Magic to calculate the depth for the z buffer
       * @param wpos The world position of the fragment
       */
      float march_compute_depth(float3 wpos) {
        float4 clippos = mul(UNITY_MATRIX_IT_MV, float4(wpos, 1.0));
        return clippos.z;
      }

      struct fragmentInput {
        float4 position : SV_POSITION;
        float4 worldpos : TEXCOORD0;
        float3 viewdir : TEXCOORD1;
      };

      struct fragmentOutput {
        float4 color : SV_Target;
        float zvalue : SV_Depth;
      };

      fragmentInput vert(appdata_base i) {
        fragmentInput o;
        o.position = mul(UNITY_MATRIX_MVP, i.vertex);
        o.worldpos = mul(_Object2World, i.vertex);
        o.viewdir = -normalize(WorldSpaceViewDir(i.vertex));
        return o;
      }

      fragmentOutput frag(fragmentInput i) {
        fragmentOutput o;

        // Raycast
        float3 wpos = i.worldpos.xyz;
        float output = march_raycast(wpos, i.viewdir, _far, _step);
        float light = 1.0 - march_lighting(wpos, output, _far, _lightStep);
        float depth = march_compute_depth(wpos);

        // Generate fragment color
        float4 color = lerp(_light, _dark, light);

        // Debugging: Depth
        float4 debug_depth = float4(depth, depth, depth, 1);
        color = IF(_debugDepth, debug_depth, color);

        // Debugging: Color
        float4 debug_light = float4(light, light, light, 1);
        color = IF(_debugLight, debug_light, color);

        // Always apply the depth map
        color.a = output;

        o.zvalue = IF(output, depth, 1);
        o.color = color;
        
        return o;
      }
      ENDCG
    }
  }
}
