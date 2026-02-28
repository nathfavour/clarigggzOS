const std = @import("std");

/// NeuralPort protocol for high-performance tensor offloading and RVV 1.0 control.
pub const NeuralPort = struct {
    pub const ProtocolID: u32 = 0xCAF3;

    pub const TensorOp = enum(u8) {
        matmul,
        conv2d,
        layernorm,
        softmax,
        vector_add,
    };

    pub const TensorDescriptor = struct {
        base_addr: u64,
        shape: [4]u16,
        data_type: enum(u8) { fp16, bf16, int8, fp32 },
    };

    pub const Request = struct {
        op: TensorOp,
        inputs: [2]TensorDescriptor,
        output: TensorDescriptor,
        // Optional: Completion callback via IPC message.
        notify_done: bool = true,
    };
};
