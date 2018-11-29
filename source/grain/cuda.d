/**
   CUDA wrapper module
 */
module grain.cuda;
version(grain_cuda):

import std.traits : ReturnType, arity;
import std.typecons : RefCounted;
import std.stdio : writeln, writefln;
import std.string : toStringz, fromStringz;

import derelict.cuda;
import derelict.cudnn7;
import grain.cublas;
import grain.utility;




// TODO: support multiple GPU devices (context)
__gshared CUcontext context;
__gshared cublasHandle_t cublasHandle;
__gshared cudnnHandle_t cudnnHandle;

/// global cuda init
shared static this() {
    // Initialize the driver API
    DerelictCUDADriver.load();
    CUdevice device;
    cuInit(0);
    // Get a handle to the first compute device
    cuDeviceGet(&device, 0);
    // Create a compute device context
    cuCtxCreate(&context, 0, device);


    // init CUDA libraries
    checkCublasErrors(cublasCreate_v2(&cublasHandle));
    DerelictCuDNN7.load();
    checkCUDNN( cudnnCreate(&cudnnHandle) );
}

/// global cuda exit
shared static ~this() {
    import core.memory : GC;
    GC.collect();
    cublasDestroy_v2(cublasHandle);
    checkCUDNN( cudnnDestroy(cudnnHandle) );
    checkCudaErrors(cuCtxDestroy(context));
}

/// cuda module compiled from ptx string
struct CuModule {
    CUmodule cuModule;

    ///
    this(string ptxstr) {
        // JIT compile a null-terminated PTX string
        checkCudaErrors(cuModuleLoadData(&cuModule, cast(void*) ptxstr.toStringz));
    }

    ///
    ~this() {
        checkCudaErrors(cuModuleUnload(cuModule));
    }

    ///
    auto kernel(alias F)() {
        return Kernel!F(cuModule);
    }
}

/// global accessor for the cuda module in grain
class Global {
    import K = grain.kernel;
    private this() {}

    // Cache instantiation flag in thread-local bool
    // Thread local
    private static bool instantiated_ = false, cxxInstantiated_ = false;

    // Thread global
    private __gshared CuModule* module_, cxxModule_;

    ///
    static get() {
        if (!instantiated_) {
            synchronized(Global.classinfo) {
                module_ = new CuModule(K.cxxptx);
                instantiated_ = true;
            }
        }
        return module_;
    }

    ///
    static getCxx() {
        if (!cxxInstantiated_) {
            synchronized(Global.classinfo) {
                cxxModule_ = new CuModule(K.cxxptx);
                cxxInstantiated_ = true;
            }
        }
        return cxxModule_;
    }

    ///
    static cxxKernel(T...)(string name, T args) {
        CUfunction cuFunction;
        writeln("getFunction...");
        checkCudaErrors(cuModuleGetFunction(&cuFunction, getCxx(), name.toStringz));
        writeln("getFunction...");
        return Launcher!T(cuFunction, args);
    }

    ///
    static kernel(alias F)() {
        return get().kernel!F;
    }
}

/// ditto
auto global() {
    return Global.get();
}

// pthread error ?
// auto CUDA_POST_KERNEL_CHECK() {
//     checkCudaErrors(cudaPeekAtLastError());
// }

/// cuda kernel function launcher with runtime numbers of blocks/threads
struct Launcher(Args...) {
    CUfunction cuFunction;
    Args args;

    /// create kernel function as void[Args.length]
    auto kernelParams(T...)(T args) {
        void*[args.length] ret;
        foreach (i, a; args) {
            ret[i] = &a;
        }
        return ret;
    }

    /// detailed launch function
    void launch(uint[3] grid, uint[3] block, uint sharedMemBytes=0, CUstream stream=null) {
        checkCudaErrors(cuLaunchKernel(
                            cuFunction,
                            grid[0], grid[1], grid[2],
                            block[0], block[1], block[2],
                            sharedMemBytes, stream,
                            kernelParams(args).ptr, null));
        // CUDA_POST_KERNEL_CHECK();
    }

    // TODO __CUDA_ARCH__ < 200 512
    enum CUDA_NUM_THREADS = 1024;

    static getBlocks(uint n) {
        return (n + CUDA_NUM_THREADS - 1) / CUDA_NUM_THREADS;
    }

    /// convinient launch function
    void launch(uint n=1, uint sharedMemBytes=0, CUstream stream=null) {
        checkCudaErrors(cuLaunchKernel(
                            cuFunction,
                            getBlocks(n), 1, 1,
                            CUDA_NUM_THREADS, 1, 1,
                            sharedMemBytes, stream,
                            kernelParams(args).ptr, null));
        // CUDA_POST_KERNEL_CHECK();
    }
}


/// cuda function object called by mangled name of C++/D device function F
struct Kernel(alias F) if (is(ReturnType!F == void)) {
    // enum name = __traits(identifier, F);
    enum name = F.mangleof;
    CUfunction cuFunction;

    ///
    this(CUmodule m) {
        // writeln("mangled: ", name);
        checkCudaErrors(cuModuleGetFunction(&cuFunction, m, name.toStringz));
    }

    // TODO: compile-time type check like d-nv
    // TODO: separate this to struct Launcher
    auto call(T...)(T args) {
        static assert(args.length == arity!F);
        // Kernel launch
        // checkCudaErrors(cuCtxSynchronize());
        return Launcher!T(cuFunction, args);
    }
}

/// alias to element type of cuda storage
alias CudaElementType(M : CuPtr!T, T) = T;
/// ditto
alias CudaElementType(M : CuArray!T, T) = T;
/// ditto
alias CudaElementType(M : RefCounted!(CuPtr!T), T) = T;
/// ditto
alias CudaElementType(M : RefCounted!(CuArray!T), T) = T;

/// trait to identify cuda storage
enum bool isDeviceMemory(T) = is(typeof({
            static assert(is(typeof(T.init.ptr) == CUdeviceptr));
            static assert(is(typeof(T.init.length) == const(size_t)));
        }));

///
unittest {
    static assert(is(typeof(CuArray!float.init.ptr) == CUdeviceptr));
    static assert(is(typeof(CuArray!float.init.length) == const(size_t)));
    static assert(isDeviceMemory!(CuPtr!float));
    static assert(isDeviceMemory!(CuArray!float));
    static assert(isDeviceMemory!(RefCounted!(CuPtr!float)));
    static assert(isDeviceMemory!(RefCounted!(CuArray!float)));
    static assert(is(CudaElementType!(CuPtr!float) == float));
    static assert(is(CudaElementType!(CuArray!float) == float));
    static assert(is(CudaElementType!(RefCounted!(CuPtr!float)) == float));
    static assert(is(CudaElementType!(RefCounted!(CuArray!float)) == float));
}

/// true if length == 0
bool empty(M)(M m) if (isDeviceMemory!M) {
    return m.length == 0;
}

/// copy device memory to host (maybe reallocate in host)
ref toHost(M, T)(ref M m, scope ref T[] host) if (isDeviceMemory!M) {
    host.length = m.length;
    checkCudaErrors(cuMemcpyDtoH(host.ptr, m.ptr, CudaElementType!M.sizeof * m.length));
    return host;
}

/// copy device memory to host (CAUTION: no reallocation here)
auto toHost(M, T)(ref M m, T* host) if (isDeviceMemory!M) {
    checkCudaErrors(cuMemcpyDtoH(host, m.ptr, CudaElementType!M.sizeof * m.length));
    return host;
}

/// allocate host memory and copy device memory content
auto toHost(M)(ref M m) if (isDeviceMemory!M) {
    alias T = CudaElementType!M;
    auto host = new T[m.length];
    checkCudaErrors(cuMemcpyDtoH(host.ptr, m.ptr, T.sizeof * m.length));
    return host;
}

///
unittest {
    foreach (i; 0 .. 100) {
        auto d = CuPtr!float([3.0]);
        assert(d.toHost() == [3.0]);
    }
}


/// fat pointer in CUDA
struct CuPtr(T) {
    CUdeviceptr ptr = 0;
    const size_t length = 0;

    /// create copy of host array into device
    this(T[] host) {
        this(host.length);
        checkCudaErrors(cuMemcpyHtoD(ptr, &host[0], T.sizeof * length));
    }

    @disable this(this); // not copyable
    @disable new(size_t); // not allocatable on heap

    /// create uninitialized T.sizeof * n array in device
    this(size_t n) {
        this.length = n;
        if (n > 0) {
            checkCudaErrors(cuMemAlloc(&this.ptr, T.sizeof * this.length));
        }
    }

    /// create fat pointer from raw pointer and its length
    this(CUdeviceptr p, size_t l) {
        this.ptr = p;
        this.length = l;
    }

    /// dtor calling cuMemFree
    ~this() {
        if (ptr != 0x0) checkCudaErrors(cuMemFree(ptr));
        ptr = 0x0;
    }
}


/// duplicate cuda memory (deep copy)
auto dup(M)(ref M m) if (isDeviceMemory!M) {
    CUdeviceptr ret;
    alias T = CudaElementType!M;
    if (m.length > 0) {
        checkCudaErrors(cuMemAlloc(&ret, T.sizeof * m.length));
        checkCudaErrors(cuMemcpyDtoD(ret, m.ptr, T.sizeof * m.length));
    }
    return CuPtr!T(ret, m.length);
}


/// sub-region on CuPtr!T
struct CuArray(T) {
    import std.typecons : RefCounted;
    const RefCounted!(CuPtr!T) storage;
    CUdeviceptr ptr;
    alias ptr this;

    ///
    this(CuPtr!T storage) {
        import std.algorithm : move;
        this.storage = move(storage);
        this.ptr = this.storage.ptr;
    }

    ///
    this(CuPtr!T storage, size_t offset) {
        import std.algorithm : move;
        this.storage = move(storage);
        this.ptr = this.storage.ptr + offset;
    }

    ///
    this(RefCounted!(CuPtr!T) storage, size_t offset=0) {
        this.storage = storage;
        this.ptr = this.storage.ptr + offset;
    }

    ///
    this(T[] host) {
        this.storage = CuPtr!T(host);
        this.ptr = this.storage.ptr;
    }

    /// not allocatable on heap
    @disable new(size_t);

    /// create uninitialized T.sizeof * n array in device
    this(size_t n) {
        this.storage = CuPtr!T(n);
        this.ptr = this.storage.ptr;
    }

    ///
    @property
    const length() {
        if (this.ptr == 0) return 0;
        auto end = this.storage.ptr + this.storage.length;
        assert(end >= this.ptr);
        return end - this.ptr;
    }
}


/// deep copy inter device memory without allocation
void copy(T)(ref CuPtr!T src, ref CuPtr!T dst)
    in { assert(src.length == dst.length); }
do {
    checkCudaErrors(cuMemcpyDtoD(dst.ptr, src.ptr, T.sizeof * src.length));
}

/// fill value for N elements from the first position
/// TODO use cudnnSetTensor
ref fill_(S, V)(ref S storage, V v, size_t N) if (isDeviceMemory!S) {
    alias T = CudaElementType!S;
    auto value = T(v);
    import std.traits : isFloatingPoint;
    // static if (isFloatingPoint!T) {
    //     import derelict.cudnn7;
    //     import grain.cudnn : fill, makeCudnnTensor;
    //     auto a = S(N);
    //     checkCUDNN( cudnnSetTensor(cudnnHandle, a.makeCudnnTensor, cast(void*) a.ptr, cast(const void*) &value) );
    // } else {
    import std.conv : to;
    import std.traits : Parameters;
    mixin("alias _memset = cuMemsetD" ~  to!string(T.sizeof * 8) ~ ";");
    alias Bytes = Parameters!(_memset)[1];
    static assert(Bytes.sizeof == T.sizeof);
    _memset(storage.ptr, *(cast(Bytes*) &value), N);
    //}
    return storage;
}

/// fill value for all the element in device array
ref fill_(S, V)(ref S storage, V value) if (isDeviceMemory!S) {
    return fill_(storage, value, storage.length);
}

/// fill zero for all the element in device array
ref zero_(S)(ref S storage) if (isDeviceMemory!S) {
    return fill_(storage, CudaElementType!S(0));
}


/// create zero filled N elements array
auto zeros(S)(size_t N) if (isDeviceMemory!S) {
    import std.algorithm : move;
    auto a = CuPtr!(CudaElementType!S)(N);
    a.zero_();
    return move(a);
}


/// cuda error checker
void checkCudaErrors(string file = __FILE__, size_t line = __LINE__,
                     string mod = __MODULE__, string func = __FUNCTION__)(CUresult err) {
    import std.format;
    const(char)* name, content;
    cuGetErrorName(err, &name);
    cuGetErrorString(err, &content);
    assert(err == CUDA_SUCCESS,
           format!"%s: %s from %s @%s:%s"(
               name.fromStringz,  content.fromStringz,
               func, file, line));
}

/// cublas error checker
void checkCublasErrors(cublasStatus_t err) {
    assert(err == CUBLAS_STATUS_SUCCESS, cublasGetErrorEnum(err));
}

/// cudnn error checker
void checkCUDNN(string file = __FILE__, size_t line = __LINE__)(cudnnStatus_t err) {
    import std.conv : to;
    import std.format : format;
    assert(err == CUDNN_STATUS_SUCCESS, cudnnGetErrorString(err).fromStringz ~ format!" at %s (%d)"(file, line));
}

/// example to launch kernel
unittest {
    import grain.kernel; // : saxpy;

    // Populate input
    uint n = 16;
    auto hostA = new float[n];
    auto hostB = new float[n];
    auto hostC = new float[n];
    foreach (i; 0 .. n) {
        hostA[i] = i;
        hostB[i] = 2 * i;
        hostC[i] = 0;
    }

    // Device data
    auto devA = CuPtr!float(hostA);
    auto devB = CuPtr!float(hostB);
    auto devC = CuPtr!float(n);

    // Kernel launch
    Global.kernel!(saxpy).call(devC.ptr, devA.ptr, devB.ptr, n).launch(n);

    // Validation
    devC.toHost(hostC);
    foreach (i; 0 .. n) {
        // writefln!"%f + %f = %f"(hostA[i], hostB[i], hostC[i]);
        assert(hostA[i] + hostB[i] == hostC[i]);
    }
}


float sumNaive(S)(ref S a) if (isDeviceMemory!S) {
    import grain.kernel : sum;
    auto b = CuPtr!float([0]);
    auto N = cast(int) a.length;
    Global.kernel!sum.call(a.ptr, b.ptr, N)
        .launch(cast(uint[3]) [1U,1,1], cast(uint[3]) [1U,1,1], 0U);
    checkCudaErrors(cuCtxSynchronize());
    return b.toHost[0];
}

unittest {
    auto a = CuPtr!float([3, 4, 5]);
    assert(a.sumNaive == 3+4+5);
}



extern (C++) float sum_thrust(float*, uint n);

/// test sum
float sum(S)(ref S a) if (isDeviceMemory!S) {
    return sum_thrust(cast(float*) a.ptr, cast(uint) a.length);
}

unittest {
    auto a = CuPtr!float([2, 4, 5, 6]);
    auto b = sum(a);
    assert(b == 2+4+5+6);
}

/*
// test cxx kernel
unittest {
    auto a = CuPtr!float([3, 4, 5]);
    auto b = CuPtr!float([0]);
    auto N = cast(int) a.length;
    assert(N == 3);
    Global.cxxKernel("sum_naive", a.ptr, b.ptr, N)
        .launch(cast(uint[3]) [1U,1,1], cast(uint[3]) [1U,1,1], 0U);
    // checkCudaErrors(cuCtxSynchronize());
    writeln(b.toHost());
    assert(b.toHost()[0] == 3+4+5);
}
*/

/// example to fill value
unittest {
    auto d = CuPtr!float(3);
    d.zero_();
    auto h = d.toHost();
    assert(h == [0, 0, 0]);
    // assert(zeros!(CuPtr!float)(3).toHost() == [0, 0, 0]);
    assert(d.fill_(3).toHost() == [3, 3, 3]);
}


/// high-level axpy (y = alpha * x + y) wrapper for CuPtr
void axpy(T)(const ref CuArray!T x, ref CuArray!T y, T alpha=1, int incx=1, int incy=1)  {
    static if (is(T == float)) {
        alias axpy_ = cublasSaxpy_v2;
    } else static if (is(T == double)) {
        alias axpy_ = cublasDaxpy_v2;
    } else {
        static assert(false, "unsupported type: " ~ T.stringof);
    }
    auto status = axpy_(cublasHandle, cast(int) x.length, &alpha,
                        cast(const T*) x.ptr, incx,
                        cast(T*) y.ptr, incy);
    assert(status == CUBLAS_STATUS_SUCCESS, cublasGetErrorEnum(status));
}

/// cublas tests
unittest {
    auto a = CuArray!float([3, 4, 5]);
    auto b = CuArray!float([1, 2, 3]);
    axpy(a, b, 2.0);
    assert(a.toHost() == [3, 4, 5]);
    assert(b.toHost() == [7, 10, 13]);
}
