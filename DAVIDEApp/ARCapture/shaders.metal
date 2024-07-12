//
//  shaders.metal
//  DAVIDEApp
//
//  Created by Jussi Kalliola (TAU) on 29.9.2022.
//

#include <metal_stdlib>
using namespace metal;

/// ####################################################
///             IMAGE SHADING FUNCTIONS AND STRUCTURES
/// ####################################################

struct ImageVertex {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct TexturedQuadVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 2D image contains 4 vertices, so it just maps it to the right place on the screen.
vertex TexturedQuadVertexOut cameraVertexTransform(ImageVertex in [[stage_in]]) {
    TexturedQuadVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}


/// Takes pixel, converts it to RGB and returns it.
fragment float4 cameraFragmentShader(TexturedQuadVertexOut in [[stage_in]],
                                     constant int &confFilterMode [[ buffer(1) ]],
                                     texture2d<float, access::sample> CameraTextureRGB [[ texture(1) ]],
                                     texture2d<float, access::sample> confidenceTexture [[ texture(2) ]],
                                     texture2d<float, access::sample> depthTexture [[ texture(3) ]])
{
    
    constexpr sampler colorSampler(filter::linear);

    float4 outColor = float4(CameraTextureRGB.sample(colorSampler, in.texCoord).rgb, 1.0);
    
    float4 depthIn = depthTexture.sample(colorSampler, in.texCoord);
    float depthValue = (depthIn.r + depthIn.b + depthIn.g) / 3;

    float4 inConf = confidenceTexture.sample(colorSampler, in.texCoord);
    int confInt = int(round(255.0*(inConf.r)));

    const auto visibility = confInt >= confFilterMode;
    if(visibility==false)
        outColor=float4(0.0, 0.0, 0.0, 0.0);
    
    
    
    return outColor;
}

// for depth. Takes pixel, converts it to RGB and returns it.
fragment float4 depthFragmentShader(TexturedQuadVertexOut in [[stage_in]],
                                    constant int &confFilterMode [[ buffer(1) ]],
                                    texture2d<float, access::sample> depthTexture [[ texture(1) ]],
                                    texture2d<float, access::sample> confidenceTexture [[ texture(2) ]])
{
    
    constexpr sampler colorSampler(filter::linear);
    float4 inColor = depthTexture.sample(colorSampler, in.texCoord);
    float4 inConf = confidenceTexture.sample(colorSampler, in.texCoord);
    
    float value = (inColor.r + inColor.b + inColor.g) / 3;
    
    float4 outColor = float4(value, value, value, 1.0);
    
    int confInt = int(round(255.0*(inConf.r)));
    
    const auto visibility = confInt >= confFilterMode;
    if(visibility==false)
        outColor=float4(1.0, 1.0, 1.0, 1.0);
        
    return outColor;
}


/// ############################
///             CONVERT YUV TO RGB
/// ############################

kernel void YUVColorConversion(texture2d<float, access::read> cameraTextureY [[texture(0)]],
                               texture2d<float, access::sample> cameraTextureCbCr [[ texture(1) ]],
                               texture2d<float, access::write> outTexture [[texture(2)]],
                               uint2 gid [[thread_position_in_grid]])
{
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4( 1.0000f,  1.0000f,  1.0000f, 0.0000f),
        float4( 0.0000f, -0.3441f,  1.7720f, 0.0000f),
        float4( 1.4020f, -0.7141f,  0.0000f, 0.0000f),
        float4(-0.7010f,  0.5291f, -0.8860f, 1.0000f)
    );

    uint2 uvCoords = uint2(gid.x / 2, gid.y / 2);
    
    float4 ycbcr = float4(cameraTextureY.read(gid).r,
                          cameraTextureCbCr.read(uvCoords).rg, 1.0);

    float4 outColor = ycbcrToRGBTransform * ycbcr;

    outTexture.write(outColor, gid);
}


