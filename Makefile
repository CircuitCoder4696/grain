.PHONY: test clean kernel example-mnist example-char-rnn cuda-deps install-hdf5 doc examples

HDF5_URL := https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8/hdf5-1.8.15-patch1/bin/linux-centos7-x86_64/hdf5-1.8.15-patch1-linux-centos7-x86_64-static.tar.gz
HDF5_ROOT := $(shell basename $(HDF5_URL) .tar.gz)

CUDA_COMPUTE_CAPABILITY := `tool/grain-compute-capability 0`
CUDA_BIT := $(shell getconf LONG_BIT)
NO_CUDA := false
DUB_BUILD := unittest


ifeq ($(NO_CUDA),true)
	DUB_OPTS = -b=$(DUB_BUILD)
else
	CUDA_DEPS = tool/grain-compute-capability source/grain/kernel.di kernel/kernel_lib.ptx
	DUB_OPTS = -b=cuda-$(DUB_BUILD)
endif


test: $(CUDA_DEPS)
	dub test --compiler=$(DC) $(DUB_OPTS)

cuda-deps: $(CUDA_DEPS)

tools/grain-compute-capability: tools/compute_capability.d
	cd tools; dub build -b=compute-capability

kernel/kernel_lib.ptx: kernel/kernel_lib.cu
	# clang-6.0 -c -S -emit-llvm $< --cuda-gpu-arch=sm_$(CUDA_COMPUTE_CAPABILITY)
	# llc-6.0 -mcpu=sm_$(CUDA_COMPUTE_CAPABILITY) $(shell basename -s .cu $<)-cuda-nvptx64-nvidia-cuda-sm_$(CUDA_COMPUTE_CAPABILITY).ll -o $@
	nvcc -ptx -arch=sm_$(CUDA_COMPUTE_CAPABILITY) $< -o $@ -std=c++11 -use_fast_math

# kernel/kernel.di: kernel/kernel.d kernel/kernel_lib.ptx
# 	ldc2 $< --mdcompute-targets=cuda-$(CUDA_COMPUTE_CAPABILITY)0 -H -Hd kernel -mdcompute-file-prefix=$(shell basename -s .d $<) -I=source
# # 	mv $(shell basename -s .d $<)_cuda$(CUDA_COMPUTE_CAPABILITY)0_$(CUDA_BIT).ptx $@

source/grain/kernel.di: kernel/kernel.di kernel/kernel_lib.ptx
	# cat kernel/$(shell basename -s .ptx $<).di     > $@
	cat kernel/kernel.di     > $@
	# @echo "/**"                                   >> $@
	# @echo " * generated PTX (see Makefile %.di) " >> $@
	# @echo "**/"                                   >> $@
	# @echo 'enum ptx = q"EOS'                      >> $@
	# @cat kernel/kernel.ptx                        >> $@
	# @echo 'EOS";'                                 >> $@
	@echo "/**"                                   >> $@
	@echo " * generated PTX (see Makefile %.di) " >> $@
	@echo "**/"                                   >> $@
	@echo 'enum cxxptx = q"EOS'                   >> $@
	@cat kernel/kernel_lib.ptx                    >> $@
	@echo 'EOS";'                                 >> $@

tool/%.out: tool/%.cu
	nvcc $< -o $@ -lcuda -std=c++11

clean:
	find . -type f -name "*.ll" -print -delete
	find . -type f -name "*.ptx" -print -delete
	# find . -type f -name "*.di" -print -delete
	find . -type f -name "*.out" -print -delete
	find . -type f -name "*.lst" -print -delete	
	rm -fv *.a

# example-mnist:
# 	dub --config=example-mnist --compiler=ldc2 $(DUB_OPTS)

# example-mnist-cnn:
# 	dub --config=example-mnist-cnn --compiler=ldc2 $(DUB_OPTS)

# example-char-rnn:
# 	dub --config=example-char-rnn --compiler=ldc2 $(DUB_OPTS)

example-%:
	dub build --config=$@ $(DUBOPTS)

examples: example-mnist example-mnist-cnn example-char-rnn example-cifar example-ptb repl jupyterd

$(HDF5_ROOT):
	wget $(HDF5_URL)
	tar -xvf $(HDF5_ROOT).tar.gz

libsz.a: $(HDF5_ROOT)
	cp -f $(HDF5_ROOT)/lib/libsz.a .

libhdf5.a: $(HDF5_ROOT)
	cp -f $(HDF5_ROOT)/lib/libhdf5.a .

libhdf5_hl.a: $(HDF5_ROOT)
	cp -f $(HDF5_ROOT)/lib/libhdf5_hl.a .

install-hdf5: libhdf5.a libhdf5_hl.a libsz.a

adrdox:
	git clone https://github.com/adamdruppe/adrdox.git --depth 1

adrdox/doc2: adrdox
	cd adrdox; make

doc: adrdox/doc2
	./adrdox/doc2 -u -i source
	# mv generated-docs docs
