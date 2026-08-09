package ai.onnxruntime;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.Buffer;
import java.nio.ByteBuffer;

/** Compatibility bridge for ONNX UINT16 tensors, which have no OnnxJavaType entry. */
public final class UnsignedOnnxTensorFactory {
    private static final Method CREATE_TENSOR = resolveCreateTensor();

    private UnsignedOnnxTensorFactory() {}

    public static OnnxTensor createUInt16Tensor(
            OrtEnvironment environment,
            ByteBuffer buffer,
            long[] shape) throws OrtException {
        if (!buffer.isDirect()) {
            throw new IllegalArgumentException("UINT16 tensor buffer must be direct");
        }
        TensorInfo.OnnxTensorType onnxType =
                TensorInfo.OnnxTensorType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16;
        TensorInfo info = new TensorInfo(shape, OnnxJavaType.INT16, onnxType);
        try {
            long handle = (long) CREATE_TENSOR.invoke(
                    null,
                    OnnxRuntime.ortApiHandle,
                    environment.defaultAllocator.handle,
                    buffer,
                    buffer.position(),
                    (long) buffer.remaining(),
                    shape,
                    onnxType.value);
            return new OnnxTensor(
                    handle,
                    environment.defaultAllocator.handle,
                    info,
                    buffer,
                    false);
        } catch (IllegalAccessException error) {
            throw new IllegalStateException("ONNX UINT16 tensor bridge is inaccessible", error);
        } catch (InvocationTargetException error) {
            Throwable cause = error.getCause();
            if (cause instanceof OrtException) throw (OrtException) cause;
            throw new IllegalStateException("ONNX UINT16 tensor creation failed", cause);
        }
    }

    private static Method resolveCreateTensor() {
        try {
            Method method = OnnxTensor.class.getDeclaredMethod(
                    "createTensorFromBuffer",
                    long.class,
                    long.class,
                    Buffer.class,
                    int.class,
                    long.class,
                    long[].class,
                    int.class);
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException error) {
            throw new ExceptionInInitializerError(error);
        }
    }
}
