I benchmarked 3 embedding backends on the same laptop — CPU, Intel iGPU (OpenVINO), and NVIDIA RTX 3060 (CUDA) — and the results were interesting.

I'm building corvia, an organizational memory system for AI agents. It needs fast embedding inference for semantic search. I had three compute backends sitting in one machine and wanted to know: which one should I default to?

The twist: the Intel integrated GPU consistently beat the NVIDIA discrete GPU. 51ms vs 56ms per embed. Not a huge margin, but it held across every input length I tested.

The reason is actually straightforward. The embedding model (nomic-embed-text-v1.5, ~137M params) is small enough that the computation finishes quickly on either GPU — but the discrete GPU pays a tax moving tensors over PCIe to VRAM. The iGPU shares system memory, so that copy never happens.

Important caveat: this does NOT mean integrated GPUs are better than discrete GPUs in general. For bigger models or larger batches, the RTX 3060's 3840 CUDA cores and 6GB VRAM would pull ahead. These results are specific to this model size, in this pipeline, on this hardware. (Slide 6 has all the caveats.)

I also added per-stage instrumentation to the server. Turns out embedding inference is only ~10ms — about 9% of total request time. The HNSW vector search and graph expansion take ~94ms. The backend everyone benchmarks is less than a tenth of what the user actually experiences. (Slide 3 has the waterfall.)

The practical outcome: corvia-inference now defaults to OpenVINO for embeddings and CUDA for chat/LLM, keeping both GPUs busy. You can switch backends at runtime with one command, no restart needed.

#LocalInference #EmbeddingModels #ONNX #CUDA #OpenVINO #Rust #AIInfrastructure #DevJourney
