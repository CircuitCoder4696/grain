// @compute(CompileFor.deviceOnly) module kernel;
/++

NOTE: now every implementation is written in kernel_lib.cu. here are only definitions.

 +/

// import ldc.dcompute : GlobalPointer, kernel, compute, CompileFor;
// import dcompute.std.index;
// import dcompute.std.atomic;
// import dcompute.std.sync;

nothrow @nogcextern(C++) :

// pragma(LDC_intrinsic, "llvm.log2")
// float _log2(float);

// pragma(LDC_intrinsic, "llvm.nvvm.atomic.load.add.f32.p1f32")
// float atomicAdd(out GlobalPointer!float, float);

// @kernel void saxpy(T)(T* res,
//                    const T* x,
//                    const T* y,
//                    int N);

/* @kernel */
void saxpy(float* res, const float* x, const float* y, int N);
// {
//     auto i = GlobalIndex.x;
//     if (i >= N) return;
//     res[i] = x[i] + y[i];
// }

/* @kernel */
void relu(float* x, int N);
// {
//     auto i = GlobalIndex.x;
//     if (i >= N) return;
//     if (x[i] < 0) x[i] = 0;
// }

/* @kernel */
void reluGrad(float* gx, const float* gy, const float* x, int N);
// {
//     auto i = GlobalIndex.x;
//     if (i >= N) return;
//     gx[i] = (x[i] <= 0) ? 0 : gy[i];
// }

// http://www.toffee.jp/streaming/gpgpu/gpgpu_programming/2015/gpgpu_programming07.pdf

/* @kernel */
void sum(const float* x, float* result, int N);

/* @kernel */
void sum_faster(const float* x, float* result, uint n, uint N);

/* @kernel */
void nll(float* loss, uint* count, const float* logp, const int* targetId,
        int ignoreIndex, uint batchSize, int logpStride);

/* @kernel */
void nllGrad(float* glogP, float coeff, const int* targetId, int ignoreIndex,
        uint batchSize, int logpStride);

/* @kernel */
void addBias(float* y, const float* b, uint blen, uint ylen);

/* @kernel */
void addBiasGrad(const float* gy, float* gb, uint blen, uint ylen);

/* @kernel */
void reciprocal(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void log(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void log2(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void log10(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void exp(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void exp2(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void exp10(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void sin(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void cos(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void tan(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void pow(float power, float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void powGrad(float power, float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void neg(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void abs(float* x, uint len, uint ndim, const uint* shape, const uint* strides);
/* @kernel */
void absGrad(float* x, uint len, uint ndim, const uint* shape, const uint* strides);

/* @kernel */
void embedding(const float* w, const int* x, float* y, uint nvocab, uint nembed, uint nbatch);
/* @kernel */
void embeddingGrad(float* gw, const int* x, const float* gy, uint nvocab, uint nembed,
        uint nbatch);
void huber(float* output, const float* predict, const float* target,
        float threshold, uint len, uint ndim, const uint* shape, const uint* strides);
void huberGrad(float* gradPredict, const float* predict, const float* target,
        float threshold, uint len, uint ndim, const uint* shape, const uint* strides);
