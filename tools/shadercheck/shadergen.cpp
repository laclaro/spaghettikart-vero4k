// Expands SpaghettiKart's OpenGL shader template (default.shader.glsl, both stages) with the GLES2 context
// for many colour-combiner configurations, so the output can be validated offline (glslangValidator, GLSL ES 1.00).
// usage: shadergen <default.shader.glsl> <outdir> <count>
#include <prism/processor.h>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <random>
#include <set>
#include <sstream>
#include <string>

enum {
    SHADER_0,
    SHADER_INPUT_1,
    SHADER_INPUT_2,
    SHADER_INPUT_3,
    SHADER_INPUT_4,
    SHADER_INPUT_5,
    SHADER_INPUT_6,
    SHADER_INPUT_7,
    SHADER_TEXEL0,
    SHADER_TEXEL0A,
    SHADER_TEXEL1,
    SHADER_TEXEL1A,
    SHADER_1,
    SHADER_COMBINED,
    SHADER_NOISE
};
enum Opt { ALPHA, FOG, TEXTURE_EDGE, NOISE, _2CYC, ALPHA_THRESHOLD, INVISIBLE, GRAYSCALE,
           T0_CLAMP_S, T0_CLAMP_T, T1_CLAMP_S, T1_CLAMP_T, T0_MASK, T1_MASK, T0_BLEND, T1_BLEND, PRIM_DEPTH };
#define OPT(o) (1u << (o))
enum FilteringMode { FILTER_THREE_POINT, FILTER_LINEAR, FILTER_NONE };

struct CCFeatures {
    int c[2][2][4];
    bool opt_alpha, opt_fog, opt_texture_edge, opt_noise, opt_2cyc, opt_alpha_threshold, opt_invisible,
        opt_grayscale, opt_prim_depth;
    bool usedTextures[2], used_masks[2], used_blend[2], clamp[2][2];
    int numInputs;
    bool do_single[2][2], do_multiply[2][2], do_mix[2][2], color_alpha_same[2];
};

// Same derivation as gfx_cc_get_features() in libultraship/src/fast/interpreter.cpp.
static void get_features(uint64_t id0, uint64_t id1, CCFeatures* f) {
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++)
            for (int k = 0; k < 4; k++)
                f->c[i][j][k] = id0 >> (i * 32 + j * 16 + k * 4) & 0xf;
    f->opt_alpha = id1 & OPT(ALPHA);
    f->opt_fog = id1 & OPT(FOG);
    f->opt_texture_edge = id1 & OPT(TEXTURE_EDGE);
    f->opt_noise = id1 & OPT(NOISE);
    f->opt_2cyc = id1 & OPT(_2CYC);
    f->opt_alpha_threshold = id1 & OPT(ALPHA_THRESHOLD);
    f->opt_invisible = id1 & OPT(INVISIBLE);
    f->opt_grayscale = id1 & OPT(GRAYSCALE);
    f->opt_prim_depth = id1 & OPT(PRIM_DEPTH);
    f->clamp[0][0] = id1 & OPT(T0_CLAMP_S);
    f->clamp[0][1] = id1 & OPT(T0_CLAMP_T);
    f->clamp[1][0] = id1 & OPT(T1_CLAMP_S);
    f->clamp[1][1] = id1 & OPT(T1_CLAMP_T);
    f->usedTextures[0] = f->usedTextures[1] = false;
    f->used_masks[0] = f->used_masks[1] = false;
    f->used_blend[0] = f->used_blend[1] = false;
    f->numInputs = 0;
    for (int c = 0; c < 2; c++)
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 4; j++) {
                int v = f->c[c][i][j];
                if (v >= SHADER_INPUT_1 && v <= SHADER_INPUT_7 && v > f->numInputs)
                    f->numInputs = v;
                if (v == SHADER_TEXEL0 || v == SHADER_TEXEL0A) {
                    f->usedTextures[0] = true;
                    if (f->opt_2cyc)
                        f->usedTextures[1] = true;
                }
                if (v == SHADER_TEXEL1 || v == SHADER_TEXEL1A) {
                    f->usedTextures[1] = true;
                    if (f->opt_2cyc)
                        f->usedTextures[0] = true;
                }
            }
    for (int c = 0; c < 2; c++) {
        f->do_single[c][0] = f->c[c][0][2] == SHADER_0;
        f->do_single[c][1] = f->c[c][1][2] == SHADER_0;
        f->do_multiply[c][0] = f->c[c][0][1] == SHADER_0 && f->c[c][0][3] == SHADER_0;
        f->do_multiply[c][1] = f->c[c][1][1] == SHADER_0 && f->c[c][1][3] == SHADER_0;
        f->do_mix[c][0] = f->c[c][0][1] == f->c[c][0][3];
        f->do_mix[c][1] = f->c[c][1][1] == f->c[c][1][3];
        f->color_alpha_same[c] = (id0 >> c * 32 & 0xffff) == (id0 >> (c * 32 + 16) & 0xffff);
    }
    if (f->usedTextures[0] && (id1 & OPT(T0_MASK)))
        f->used_masks[0] = true;
    if (f->usedTextures[1] && (id1 & OPT(T1_MASK)))
        f->used_masks[1] = true;
    if (f->usedTextures[0] && (id1 & OPT(T0_BLEND)))
        f->used_blend[0] = true;
    if (f->usedTextures[1] && (id1 & OPT(T1_BLEND)))
        f->used_blend[1] = true;
}

// shader_item_to_str() / get_bool() / append_formula(), extracted from gfx_opengl.cpp by check-shaders.sh.
#include "formula.inc"

static size_t numFloats = 0;
static prism::ContextTypes* UpdateFloats(prism::ContextTypes* _, prism::ContextTypes* num) {
    numFloats += std::get<int>(*num);
    return nullptr;
}

static std::string slurp(const char* path) {
    std::ifstream in(path);
    std::stringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

static std::string build_fs(const std::string& tmpl, CCFeatures& cc, bool three_point, bool srgb) {
    prism::Processor processor;
    prism::ContextItems ctx = {
        { "VERTEX_SHADER", false },
        { "o_prim_depth", cc.opt_prim_depth },
        { "o_c", M_ARRAY(cc.c, int, 2, 2, 4) },
        { "o_alpha", cc.opt_alpha },
        { "o_fog", cc.opt_fog },
        { "o_texture_edge", cc.opt_texture_edge },
        { "o_noise", cc.opt_noise },
        { "o_2cyc", cc.opt_2cyc },
        { "o_alpha_threshold", cc.opt_alpha_threshold },
        { "o_invisible", cc.opt_invisible },
        { "o_grayscale", cc.opt_grayscale },
        { "o_textures", M_ARRAY(cc.usedTextures, bool, 2) },
        { "o_masks", M_ARRAY(cc.used_masks, bool, 2) },
        { "o_blend", M_ARRAY(cc.used_blend, bool, 2) },
        { "o_clamp", M_ARRAY(cc.clamp, bool, 2, 2) },
        { "o_inputs", cc.numInputs },
        { "o_do_mix", M_ARRAY(cc.do_mix, bool, 2, 2) },
        { "o_do_single", M_ARRAY(cc.do_single, bool, 2, 2) },
        { "o_do_multiply", M_ARRAY(cc.do_multiply, bool, 2, 2) },
        { "o_color_alpha_same", M_ARRAY(cc.color_alpha_same, bool, 2) },
        { "FILTER_THREE_POINT", FILTER_THREE_POINT },
        { "FILTER_LINEAR", FILTER_LINEAR },
        { "FILTER_NONE", FILTER_NONE },
        { "srgb_mode", srgb },
        { "SHADER_0", SHADER_0 },
        { "SHADER_INPUT_1", SHADER_INPUT_1 },
        { "SHADER_INPUT_2", SHADER_INPUT_2 },
        { "SHADER_INPUT_3", SHADER_INPUT_3 },
        { "SHADER_INPUT_4", SHADER_INPUT_4 },
        { "SHADER_INPUT_5", SHADER_INPUT_5 },
        { "SHADER_INPUT_6", SHADER_INPUT_6 },
        { "SHADER_INPUT_7", SHADER_INPUT_7 },
        { "SHADER_TEXEL0", SHADER_TEXEL0 },
        { "SHADER_TEXEL0A", SHADER_TEXEL0A },
        { "SHADER_TEXEL1", SHADER_TEXEL1 },
        { "SHADER_TEXEL1A", SHADER_TEXEL1A },
        { "SHADER_1", SHADER_1 },
        { "SHADER_COMBINED", SHADER_COMBINED },
        { "SHADER_NOISE", SHADER_NOISE },
        { "o_three_point_filtering", three_point },
        { "append_formula", (InvokeFunc)append_formula },
        // GLES2 context, as in BuildFsShader() under USE_OPENGLES2.
        { "GLSL_VERSION", "#version 100\nprecision mediump float;" },
        { "attr", "varying" },
        { "opengles", false },
        { "gles2", true },
        { "core_opengl", false },
        { "texture", "texture2D" },
        { "vOutColor", "gl_FragColor" },
    };
    processor.populate(ctx);
    processor.load(tmpl);
    return processor.process();
}

static std::string build_vs(const std::string& tmpl, CCFeatures& cc) {
    numFloats = 4;
    prism::Processor processor;
    prism::ContextItems ctx = {
        { "VERTEX_SHADER", true },
        { "o_prim_depth", cc.opt_prim_depth },
        { "o_textures", M_ARRAY(cc.usedTextures, bool, 2) },
        { "o_clamp", M_ARRAY(cc.clamp, bool, 2, 2) },
        { "o_fog", cc.opt_fog },
        { "o_grayscale", cc.opt_grayscale },
        { "o_alpha", cc.opt_alpha },
        { "o_inputs", cc.numInputs },
        { "update_floats", (InvokeFunc)UpdateFloats },
        // GLES2 context, as in BuildVsShader() under USE_OPENGLES2.
        { "GLSL_VERSION", "#version 100" },
        { "attr", "attribute" },
        { "out", "varying" },
        { "opengles", false },
        { "gles2", true },
    };
    processor.populate(ctx);
    processor.load(tmpl);
    return processor.process();
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <default.shader.glsl> <outdir> <count>\n", argv[0]);
        return 2;
    }
    const std::string tmpl = slurp(argv[1]);
    const std::string outdir = argv[2];
    const int count = atoi(argv[3]);

    std::mt19937_64 rng(1234);
    std::set<std::pair<uint64_t, uint64_t>> seen;
    int written = 0;
    for (int n = 0; written < count && n < count * 20; n++) {
        uint64_t id0 = 0;
        for (int k = 0; k < 16; k++) {
            // Combiner slots hold SHADER_* values 0..14; bias towards common inputs and zero.
            static const int pool[] = { SHADER_0, SHADER_0, SHADER_INPUT_1, SHADER_INPUT_2, SHADER_INPUT_3,
                                        SHADER_INPUT_4, SHADER_TEXEL0, SHADER_TEXEL0A, SHADER_TEXEL1,
                                        SHADER_TEXEL1A, SHADER_1, SHADER_COMBINED, SHADER_NOISE };
            id0 |= (uint64_t)pool[rng() % (sizeof(pool) / sizeof(pool[0]))] << (k * 4);
        }
        // Option bits up to and including PRIM_DEPTH (PRISM_SHADER selects custom shaders, not tested here).
        uint64_t id1 = rng() & 0x1FFFF;
        if (n < 4) {
            // Also cover the simplest and the "everything enabled" cases explicitly.
            id0 = n < 2 ? 0 : id0;
            id1 = n % 2 ? 0x1FFFF : 0;
        }
        if (!seen.insert({ id0, id1 }).second)
            continue;
        CCFeatures cc;
        get_features(id0, id1, &cc);
        const bool three_point = written % 2 == 0;
        const bool srgb = written % 5 == 0;
        char base[256];
        snprintf(base, sizeof(base), "%s/s%04d_%016llx_%05llx", outdir.c_str(), written, (unsigned long long)id0,
                 (unsigned long long)id1);
        std::ofstream(std::string(base) + ".vert") << build_vs(tmpl, cc);
        std::ofstream(std::string(base) + ".frag") << build_fs(tmpl, cc, three_point, srgb);
        written++;
    }
    printf("generated %d shader pairs\n", written);
    return 0;
}
