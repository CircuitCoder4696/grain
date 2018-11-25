module grain;
/++

Chainer like autograd and neural networks library

 +/

/**
   License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).
   Authors:
   $(LINK2 https://github.com/ShigekiKarita, Shigeki Karita),

   See_Also:
   $(LINK2 https://github.com/ShigekiKarita/grain, Github repo)
   $(BR)
   $(LINK2 https://chainer.org, chainer)
   $(BR)
   $(LINK2 https://pytorch.org, pytorch)
   $(BR)
*/


public:
import grain.autograd;
import grain.chain;
import grain.config;
import grain.serializer;
import grain.optim;
import grain.metric;

version (grain_cuda) import grain.cuda;
