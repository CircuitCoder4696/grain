/++
Character Recurrent Neural Networks in numir.

See_Also:

Minimal character-level Vanilla RNN model. Written by Andrej Karpathy (@karpathy)
https://gist.github.com/karpathy/d4dee566867f8291f086
 +/

import std.array : array;
import std.stdio;
import std.datetime.stopwatch; //  : StopWatch, seconds, TickDuration;
// import std.conv : to;
import std.file : readText, exists;
import std.algorithm : stdmap = map;
import std.typecons : tuple;
import std.net.curl : get;

import numir;
import mir.random.variable : discreteVar;
import mir.random;
import mir.ndslice;

static import grain.config;
import grain.autograd;
import grain.optim;


struct RNN(alias Storage, T=float) {
    import grain.chain;
    alias L = Linear!(T, Storage);
    Embedding!(T, Storage) wx;
    L wh, wy;

    this(uint nvocab, int nunits) {
        import grain.utility : castArray;
        this.wx = Embedding!(T, Storage)(nvocab, nunits);
        this.wh = L(nunits, nunits);
        this.wy = L(nunits, nvocab);

        // this.wx.weight.sliced[] = normal!float(this.wx.weight.shape.castArray!size_t) * 0.01;
        // this.wh.weight.sliced[] = normal!float(this.wx.weight.shape.castArray!size_t) * 0.01;
        // this.wy.weight.sliced[] = normal!float(this.wx.weight.shape.castArray!size_t) * 0.01;
        // this.wh.bias.sliced[] = 0;
        // this.wy.bias.sliced[] = 0;
    }

    /// framewise batch input
    auto opCall(Variable!(int, 1, Storage) x, Variable!(float, 2, Storage) hprev) {
        import std.typecons : tuple;
        auto h = tanh(this.wx(x) + this.wh(hprev));
        auto y = logSoftmax(this.wy(h));
        return tuple!("y", "h")(y, h);
    }

    auto sample(int seed_ix, size_t n, Variable!(float, 2, Storage) hprev) {
        // Random gen;
        import numir : squeeze;
        auto gen = Random(unpredictableSeed);
        import mir.math : exp, sum;
        auto x = [seed_ix].variable;
        int[] ret = [seed_ix];
        foreach (t; 0 .. n) {
            auto next = this.opCall(x, hprev);
            auto p = map!exp(next.y.sliced).slice;
            auto ix = cast(int) discreteVar(p.squeeze!0.ndarray)(gen);
            ret ~= [ix];
            hprev = next.h;
            x = [ix].variable;
        }
        return ret;
    }

    /// batch x frame input
    auto accumGrad(Slice!(int*, 2, Universal) xs, Variable!(float, 2, Storage) hprev) {
        grain.config.backprop = true;
        auto loss = new Variable!(float, 0, Storage)[xs.length!1-1];
        auto hs = new Variable!(float, 2, Storage)[xs.length!1];
        hs[0] = hprev;
        loss[0] = 0f.variable;
        foreach (t; 0 .. xs.length!1 - 1) {
            auto x = xs[0..$, t].variable.to!Storage;
            auto result = this.opCall(x, hs[t]);
            hs[t+1] = result.h;
            loss[t] = negativeLogLikelihood(result.y, xs[0..$, t+1].variable.to!Storage);
        }
        auto sumLoss = 0.0;
        foreach_reverse(l; loss) {
            l.backward();
            sumLoss += l.to!HostStorage.data[0];
        }
        hs[$-1].detach(); // unchain backprop
        return tuple!("loss", "hprev")(sumLoss, hs[$-1]);
    }
}

void main() {
    import C = std.conv;
    import mir.math : log;

    // data I/O
    if (!"data/".exists) {
        import std.file : mkdir;
        mkdir("data");
    }
    if (!"data/input.txt".exists) {
        import std.net.curl : download;
        download("https://raw.githubusercontent.com/karpathy/char-rnn/master/data/tinyshakespeare/input.txt", "data/input.txt");
    }
    auto data = C.to!dstring(readText("data/input.txt"));
    int[dchar] char2idx;
    dchar[] idx2char;
    foreach (c; data) {
        if (c !in char2idx) {
            char2idx[c] = cast(int) idx2char.length;
            idx2char ~= [c];
        }
    }
    auto vocabSize = cast(uint) idx2char.length;
    writefln!"data has %d characters, %d unique."(data.length, vocabSize);

    // hyperparameters
    auto hiddenSize = 100; // size of hidden layer of neurons
    auto seqLength = 25;   // number of steps to unroll the RNN for
    auto learningRate = 0.01;
    auto maxIter = 10000;
    auto logIter = maxIter / 100;
    auto batchSize = 1;

    // model parameters
    alias Storage = HostStorage;
    auto model = RNN!Storage(vocabSize, hiddenSize);

    // for optim
    auto optim = AdaGrad!(typeof(model))(model, learningRate);
    auto smoothLoss = -log(1.0 / vocabSize) * seqLength;
    size_t beginId = 0;
    auto hprev = zeros!float(batchSize, hiddenSize).variable(true).to!Storage;
    auto sw = StopWatch(AutoStart.yes);
    foreach (nIter; 0 .. maxIter) {
        // prepare inputs (we're sweeping from left to right in steps seq_length long)
        if (beginId + seqLength + 1 >= data.length || nIter == 0) {
            // reset RNN memory
            hprev = zeros!float(batchSize, hiddenSize).variable(true).to!Storage;
            beginId = 0; // go from start of data
        }
        auto ids = data[beginId .. beginId + seqLength + 1].stdmap!(c => char2idx[c]).array;
        // sample from the model now and then
        if (nIter % logIter == 0) {
            auto sampleIdx = model.sample(ids[0], 200, hprev);
            auto txt = C.to!dstring(sampleIdx.stdmap!(ix => idx2char[ix]));
            writeln("-----\n", txt, "\n-----");
        }

        // forward seq_length characters through the net and fetch gradient
        model.zeroGrad();
        auto ret = model.accumGrad(ids.sliced.unsqueeze!0, hprev);
        optim.update();
        smoothLoss = smoothLoss * 0.999 + ret.loss * 0.001;
        hprev = ret.hprev;
        if (nIter % logIter == 0) {
            writefln!"iter %d, loss: %f, iter/sec: %f"(
                nIter, smoothLoss,
                cast(double) logIter / (C.to!(TickDuration)(sw.peek()).msecs * 1e-3));
            sw.reset();
        }
        beginId += seqLength; // move data pointer
    }
}
