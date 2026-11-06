#include "desktop_channel.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wincrypt.h>
#include <wrl/client.h>

#include <filesystem>

#include "utils.h"

namespace {
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

HRESULT ChoosePath(HWND window, const std::string& method, std::string* selected) {
  const bool folder = method == "chooseDirectory";
  ComPtr<IFileOpenDialog> dialog;
  HRESULT status = ::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(dialog.GetAddressOf()));
  if (FAILED(status)) return status;

  DWORD options = 0;
  status = dialog->GetOptions(&options);
  if (FAILED(status)) return status;
  status = dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR |
                              (folder ? FOS_PICKFOLDERS : FOS_FILEMUSTEXIST));
  if (FAILED(status)) return status;
  if (!folder) {
    const COMDLG_FILTERSPEC filter = method == "chooseGlossary"
        ? COMDLG_FILTERSPEC{L"CSV (*.csv)", L"*.csv"}
        : COMDLG_FILTERSPEC{L"PDF (*.pdf)", L"*.pdf"};
    status = dialog->SetFileTypes(1, &filter);
    if (FAILED(status)) return status;
  }

  status = dialog->Show(window);
  if (FAILED(status)) return status;

  ComPtr<IShellItem> item;
  status = dialog->GetResult(item.GetAddressOf());
  if (FAILED(status)) return status;

  PWSTR path = nullptr;
  status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  if (SUCCEEDED(status)) *selected = Utf8FromUtf16(path);
  ::CoTaskMemFree(path);
  return status;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDesktopChannel(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "pdfmath/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "choosePdf" || method == "chooseDirectory" ||
            method == "chooseGlossary") {
          std::string path;
          const HRESULT status = ChoosePath(window, method, &path);
          if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            result->Success();
          } else if (FAILED(status) || path.empty()) {
            result->Error("dialog_failed", "Windows file selection failed.");
          } else {
            result->Success(EncodableValue(path));
          }
        } else if (method == "protectSettings" || method == "unprotectSettings") {
          const auto* bytes = std::get_if<std::vector<uint8_t>>(call.arguments());
          if (!bytes || bytes->empty()) {
            result->Error("invalid_settings");
            return;
          }
          DATA_BLOB input{static_cast<DWORD>(bytes->size()),
                          const_cast<BYTE*>(bytes->data())};
          DATA_BLOB output{};
          const BOOL success = method == "protectSettings"
              ? ::CryptProtectData(&input, L"PDFMathTranslate", nullptr, nullptr,
                                   nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)
              : ::CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                                     CRYPTPROTECT_UI_FORBIDDEN, &output);
          if (!success) {
            result->Error("settings_encryption_failed");
            return;
          }
          std::vector<uint8_t> value(output.pbData, output.pbData + output.cbData);
          ::SecureZeroMemory(output.pbData, output.cbData);
          ::LocalFree(output.pbData);
          result->Success(EncodableValue(std::move(value)));
        } else if (method == "openPath") {
          const auto* argument = std::get_if<std::string>(call.arguments());
          if (!argument || argument->empty()) {
            result->Error("invalid_path");
            return;
          }
          const auto path = std::filesystem::u8path(*argument);
          const auto handle = ::ShellExecuteW(window, L"open", path.c_str(),
                                             nullptr, nullptr, SW_SHOWNORMAL);
          result->Success(EncodableValue(reinterpret_cast<INT_PTR>(handle) > 32));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
