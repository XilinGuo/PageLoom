#ifndef RUNNER_DESKTOP_CHANNEL_H_
#define RUNNER_DESKTOP_CHANNEL_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDesktopChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_DESKTOP_CHANNEL_H_
