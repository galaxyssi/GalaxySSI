set(GALAXYSSI_ASR_CORE_SOURCES
    audio_frontend.cpp
    audio_resampler.cpp
    audio_ring_buffer.cpp
    log_mel_extractor.cpp
    rolling_window.cpp
    streaming_frontend_session.cpp
    transcript_stabilizer.cpp
    vad_engine.cpp
)

add_library(galaxyssi_asr_core STATIC ${GALAXYSSI_ASR_CORE_SOURCES})
set_target_properties(galaxyssi_asr_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(galaxyssi_asr_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(galaxyssi_asr_core PUBLIC cxx_std_17)

add_library(galaxyssi_asr SHARED galaxyssi_asr_api.cpp ${GALAXYSSI_ASR_CORE_SOURCES})
target_include_directories(galaxyssi_asr PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(galaxyssi_asr PUBLIC cxx_std_17)

foreach(GALAXYSSI_ASR_TARGET galaxyssi_asr_core galaxyssi_asr)
    target_compile_options(${GALAXYSSI_ASR_TARGET} PRIVATE
        -O3
        -Wall
        -Wextra
        -Wpedantic
        -fvisibility=hidden
        -fvisibility-inlines-hidden
    )
endforeach()

if(ANDROID)
    find_library(GALAXYSSI_ASR_LOG_LIB log)
    find_library(GALAXYSSI_ASR_ANDROID_LIB android)
    target_link_libraries(galaxyssi_asr PRIVATE
        ${GALAXYSSI_ASR_LOG_LIB}
        ${GALAXYSSI_ASR_ANDROID_LIB}
        ${CMAKE_DL_LIBS}
    )
endif()
