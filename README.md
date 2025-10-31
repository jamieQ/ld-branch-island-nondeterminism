# ld-branch-island-nondeterminism
Example of nondeterminism when linking large binaries

Feedback #:
FB20884404

### Instructions:

From the root directory run:

```bash
./test_nondeterminism.sh --generate
```

This will do the following:

1. Generate a number of swift files (512 by default) and compile them to separate object files (takes a little while).
2. Generate a number of 'filler' padding object files to force the resulting binary to be over the arm64 branch range limit (2 files of 64MB each by default).
3. Generate a main entry point file.
4. Repeatedly run clang to link the swift objects, then the filler padding objects, then the main.o file.
5. Checks the resulting binaries & link map files for nondeterministic results.

The results of repeated links after the initial object file generation
suggest something related to the handling of branch island generation/placement
within the linker is nondeterministic. The map file output often contains
different ordering of branch islands, e.g.

```diff
12365,12371c12365,12371
< 0x104113200   0x00000004      [  0] _swift_getTypeByMangledNameInContext.island
< 0x104113204   0x00000004      [  0] _swift_getWitnessTable.island
< 0x104113208   0x00000004      [  0] _swift_getTypeByMangledNameInContextInMetadataState.island
< 0x10411320C   0x00000004      [  0] _$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC.island
< 0x104113210   0x00000004      [  0] _$ss26DefaultStringInterpolationV13appendLiteralyySSF.island
< 0x104113214   0x00000004      [  0] _$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF.island
< 0x104113218   0x00000004      [  0] _$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC.island
---
> 0x104113200   0x00000004      [  0] _$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC.island
> 0x104113204   0x00000004      [  0] _$ss26DefaultStringInterpolationV13appendLiteralyySSF.island
> 0x104113208   0x00000004      [  0] _$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzlF.island
> 0x10411320C   0x00000004      [  0] _$sSS19stringInterpolationSSs013DefaultStringB0V_tcfC.island
> 0x104113210   0x00000004      [  0] _swift_getTypeByMangledNameInContext.island
> 0x104113214   0x00000004      [  0] _swift_getWitnessTable.island
> 0x104113218   0x00000004      [  0] _swift_getTypeByMangledNameInContextInMetadataState.island
```

Sometimes nondeterminism will not appear – there are various knobs in
the scripts that can be used to try and change parameters. e.g. you can
increase the number of links performed by specifying a 'run count' parameter:

```bash
./test_nondeterminism.sh -r 100
```

The other scripts generally explain the options via the --help option.

---

N.B. Most of the scripts here were generated via LLM use, so may contain
errors or could potentially be improved.
