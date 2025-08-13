#!/bin/bash

# 检查必要工具
check_tools() {
    if ! command -v cmake &> /dev/null; then
        echo "错误: cmake 未安装！请先安装 cmake。"
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo "错误: xcodebuild 未安装！请确保 Xcode 已安装。"
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    echo "用法: $0 <平台> [--libjpeg|--turbojpeg] [--xcframework]"
    echo "可用平台: iphoneos, iphonesimulator, macosx"
    echo "库选项:"
    echo "  --libjpeg    编译 libjpeg.a (默认)"
    echo "  --turbojpeg  编译 libturbojpeg.a"
    echo "示例:"
    echo "  $0 iphoneos --turbojpeg         # 编译 iOS 真机版 turbojpeg"
    echo "  $0 iphonesimulator --libjpeg    # 编译 iOS 模拟器版 libjpeg"
    echo "  $0 iphoneos --turbojpeg --xcframework # 生成 turbojpeg 的 XCFramework"
    exit 0
}

# 解析参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --libjpeg)
                LIB_TYPE="libjpeg"
                shift
                ;;
            --turbojpeg)
                LIB_TYPE="turbojpeg"
                shift
                ;;
            --xcframework)
                BUILD_XCFRAMEWORK=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            iphoneos|iphonesimulator|macosx)
                PLATFORM=$1
                shift
                ;;
            *)
                echo "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 默认使用 libjpeg
    LIB_TYPE=${LIB_TYPE:-"libjpeg"}
}

# 收集头文件
collect_headers() {
    local headers=(
        "jconfig.h"
        "jerror.h"
        "jmorecfg.h"
        "jpeglib.h"
        "turbojpeg.h"
    )
    
    mkdir -p "../$OUTPUT_DIR/include"
    
    for header in "${headers[@]}"; do
        if [ -f "../$header" ]; then
            cp "../$header" "../$OUTPUT_DIR/include/"
        elif [ -f "../src/$header" ]; then
            cp "../src/$header" "../$OUTPUT_DIR/include/"
        fi
    done
    
    echo "头文件已复制到: $OUTPUT_DIR/include/"
}

# 主编译函数
compile_library() {
    local arch=$1
    local sdk=$2
    
    echo "正在编译 $PLATFORM (架构: $arch)..."
    
    rm -rf *
    cmake .. \
        -DCMAKE_OSX_SYSROOT=$sdk \
        -DCMAKE_OSX_ARCHITECTURES=$arch \
        -DENABLE_SHARED=OFF \
        -DCMAKE_BUILD_TYPE=Release
    
    if ! make -j8; then
        echo "编译失败！请检查错误。"
        exit 1
    fi
    
    # 根据选择的库类型复制文件
    local output_name
    case $LIB_TYPE in
        libjpeg)
            output_name="libjpeg-$arch.a"
            cp libjpeg.a "../$OUTPUT_DIR/$output_name"
            ;;
        turbojpeg)
            output_name="libturbojpeg-$arch.a"
            cp libturbojpeg.a "../$OUTPUT_DIR/$output_name"
            ;;
    esac
    
    echo "已生成: $output_name"
}

# 合并通用库
create_universal_lib() {
    local libs=()
    for arch in "${ARCHS[@]}"; do
        case $LIB_TYPE in
            libjpeg)
                libs+=("../$OUTPUT_DIR/libjpeg-$arch.a")
                ;;
            turbojpeg)
                libs+=("../$OUTPUT_DIR/libturbojpeg-$arch.a")
                ;;
        esac
    done
    
    local universal_name
    case $LIB_TYPE in
        libjpeg)
            universal_name="libjpeg-$PLATFORM.a"
            ;;
        turbojpeg)
            universal_name="libturbojpeg-$PLATFORM.a"
            ;;
    esac
    
    lipo -create "${libs[@]}" -output "../$OUTPUT_DIR/$universal_name"
    echo "Universal Library 已生成: $universal_name"
}

# 创建XCFramework
create_xcframework() {
    local xcframework_name
    case $LIB_TYPE in
        libjpeg)
            xcframework_name="libjpeg.xcframework"
            ;;
        turbojpeg)
            xcframework_name="libturbojpeg.xcframework"
            ;;
    esac
    
    xcodebuild -create-xcframework \
        -library "../$OUTPUT_DIR/lib$LIB_TYPE-iphoneos.a" \
        -library "../$OUTPUT_DIR/lib$LIB_TYPE-iphonesimulator.a" \
        -output "../$OUTPUT_DIR/$xcframework_name"
    
    echo "XCFramework 已生成: $xcframework_name"
}

# 主流程
main() {
    check_tools
    parse_arguments "$@"
    
    OUTPUT_DIR="libjpeg-turbo_output"
    # 清理输出目录
    rm -rf "$OUTPUT_DIR"
    # 设置输出目录
    mkdir -p "$OUTPUT_DIR"
    
    # 清理旧构建
    rm -rf build
    mkdir build && cd build
    
    # 根据平台设置架构
    case $PLATFORM in
        iphoneos)
            SDK=$(xcrun --sdk iphoneos --show-sdk-path)
            ARCHS=("arm64")
            ;;
        iphonesimulator)
            SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
            ARCHS=("x86_64" "arm64")
            ;;
        macosx)
            SDK=$(xcrun --sdk macosx --show-sdk-path)
            ARCHS=("x86_64" "arm64")
            ;;
    esac
    
    # 编译每个架构
    for arch in "${ARCHS[@]}"; do
        compile_library "$arch" "$SDK"
    done
    
    # 如果是多架构，合并成通用库
    if [ ${#ARCHS[@]} -gt 1 ]; then
        create_universal_lib
    else
        # 单架构直接重命名
        case $LIB_TYPE in
            libjpeg)
                mv "../$OUTPUT_DIR/libjpeg-${ARCHS[0]}.a" "../$OUTPUT_DIR/libjpeg-$PLATFORM.a"
                ;;
            turbojpeg)
                mv "../$OUTPUT_DIR/libturbojpeg-${ARCHS[0]}.a" "../$OUTPUT_DIR/libturbojpeg-$PLATFORM.a"
                ;;
        esac
    fi
    
    # 收集头文件
    collect_headers
    
    # 如果需要生成XCFramework
    if [ "$BUILD_XCFRAMEWORK" = true ] && [ "$PLATFORM" = "iphoneos" ]; then
        # 先编译模拟器版本
        cd ..
        rm -rf build
        mkdir build && cd build
        
        SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
        SIM_ARCHS=("x86_64" "arm64")
        
        for arch in "${SIM_ARCHS[@]}"; do
            compile_library "$arch" "$SIM_SDK"
        done
        
        # 合并模拟器通用库
        SIM_ARCHS=("x86_64" "arm64")
        ARCHS=("${SIM_ARCHS[@]}")
        create_universal_lib
        
        # 生成XCFramework
        create_xcframework
    fi
    
    cd ..
    echo "🎉编译完成！输出目录: $OUTPUT_DIR"
    echo "使用的库: $LIB_TYPE"
}

main "$@"
