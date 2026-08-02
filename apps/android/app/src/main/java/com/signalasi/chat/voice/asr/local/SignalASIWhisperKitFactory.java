package com.signalasi.chat.voice.asr.local;

import android.content.Context;

import com.argmaxinc.whisperkit.WhisperKit;
import com.argmaxinc.whisperkit.WhisperKitImpl;
import com.argmaxinc.whisperkit.network.ArgmaxModelDownloader;
import com.argmaxinc.whisperkit.util.SegmentTextOnlyMessageProcessor;

final class SignalASIWhisperKitFactory {
    private SignalASIWhisperKitFactory() {}

    static WhisperKit create(
            Context context,
            String model,
            WhisperKit.TextOutputCallback callback,
            ArgmaxModelDownloader downloader
    ) {
        return new WhisperKitImpl(
                context,
                model,
                WhisperKit.Builder.CPU_AND_NPU,
                WhisperKit.Builder.CPU_AND_NPU,
                callback,
                downloader,
                new SegmentTextOnlyMessageProcessor()
        );
    }
}
