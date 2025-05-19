This is a toy project of mine to implement SentencePiece in zig. I also wanted to have
Python wrapper around the library to easily check the correctness of the implementation.
I have implemented the tokenizer and the byte fallback. I have yet to implement the decoder.

This project is mainly for learning purpose, and I may not focus on it in the future. 
The python wrapper doesn't do much of an error checking or handling. 
My goal is not to implement the fastest tokenizer out there. I think there are good ones alread (kitoken for example).

But, this is probably going to be on same level as kitoken (for sentences longer than 100 characters. Kitoken doesn't use heap for smaller senteces).

However, if you want to implement a CPython extension in zig, this project may have some useful
information. You can read `setup.py` and `build.zig` to see how I implemented the extension.

Use `python setup.py build_ext --inplace` to build the extension. 
This internally runs `zig build python -Drelease-fast -Iinclude_dirs` to build the extension using zig compiler.



# Next Zteps
- [x] return ids from 
- [x] fix memory leaks
- [x] test it on some string
- [x] allow tokenization from input argument file (line by line)
- [x] check correctness between reference and sentencepiece
- [x] benchmark between sentecepiece and zig
- [x] optimize more
- [ ] add support for tokenize to piceces
- [x] benchmark with kitoken
- [x] add python bindings
- [x] make the build system easier and manageable
- [ ] add decoder
- [ ] add decoer in python
- [ ] conclude
- [ ] may be handle unknown token for the cases when bytefallback is false


# Benchmarks

Note: The benchmark are for development purpose only. First benchmark used Zig's priority queue which doesn't allow one to change the priority of the element. I have letter implemented indexed priority queue, which made the things much faster. I only tested one text file with single sentence (with longer than 100 characters (to trigger pririty queue implementation of kitoken)). I think I am at more or less at the same level as kitoken. I didn't optmize further. 

## Old Implementation (without indexed priority queue)

Benchmark 1 (5 runs): python test_zp.py
  measurement          mean ± σ            min … max           outliers
  wall_time          1.17s  ± 6.94ms    1.16s  … 1.18s           0 ( 0%)        
  peak_rss           64.9MB ± 77.6KB    64.8MB … 65.0MB          0 ( 0%)        
  cpu_cycles         5.00G  ± 34.7M     4.96G  … 5.05G           0 ( 0%)        
  instructions       10.6G  ± 6.02M     10.6G  … 10.6G           0 ( 0%)        
  cache_references   3.59M  ± 19.1K     3.57M  … 3.62M           0 ( 0%)        
  cache_misses       1.27M  ± 12.4K     1.25M  … 1.28M           0 ( 0%)        
  branch_misses      62.6M  ± 1.10M     62.0M  … 64.6M           0 ( 0%)    

## New Implementation (with indexed priority queue)

Benchmark 1 (9 runs): python test_zp.py
  measurement          mean ± σ            min … max           outliers
  wall_time           572ms ± 17.2ms     548ms …  593ms          0 ( 0%)        
  peak_rss           66.0MB ±  924KB    65.0MB … 66.9MB          0 ( 0%)        
  cpu_cycles         2.42G  ± 76.2M     2.30G  … 2.51G           0 ( 0%)        
  instructions       7.59G  ± 5.89M     7.59G  … 7.60G           0 ( 0%)        
  cache_references   3.76M  ± 80.8K     3.64M  … 3.88M           0 ( 0%)        
  cache_misses       1.44M  ± 78.2K     1.28M  … 1.52M           0 ( 0%)        
  branch_misses      5.44M  ± 1.51M     3.10M  … 7.65M           0 ( 0%) 