#include <rex/rex_app.h>
#include <rex/ui/imgui_dialog.h>
#include <rex/ui/imgui_drawer.h>
#include <imgui.h>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <system_error>

namespace fs = std::filesystem;
namespace {
constexpr const char* kRoot = "/data/LibertyRecomp";

struct Scan {
  bool folders = false, xex = false, xexp = false, update = false;
  std::string error;
};

std::string Now() {
  const std::time_t value = std::time(nullptr);
  std::tm local{};
  localtime_r(&value, &local);
  char buffer[32]{};
  std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &local);
  return buffer;
}

void Log(const std::string& line) {
  std::error_code ec;
  fs::create_directories(fs::path(kRoot) / "Diagnostics", ec);
  std::ofstream out(fs::path(kRoot) / "Diagnostics/setup-manager.log", std::ios::app);
  if (out) out << "[" << Now() << "] " << line << "\n";
}

bool HasData(const fs::path& path) {
  std::error_code ec;
  return fs::is_regular_file(path, ec) && !ec && fs::file_size(path, ec) > 0 && !ec;
}

Scan ScanFiles() {
  Scan s;
  const fs::path root(kRoot), game = root / "game";
  std::error_code ec;
  for (const auto& folder : {root / "source", game, root / "Diagnostics"}) {
    ec.clear();
    fs::create_directories(folder, ec);
    if (ec && s.error.empty()) s.error = folder.string() + ": " + ec.message();
  }
  ec.clear();
  if (!fs::exists(root / "env.txt", ec) && !ec) {
    std::ofstream env(root / "env.txt");
    if (env) env << "# Existing Liberty Recompiled settings are never overwritten.\n";
    else if (s.error.empty()) s.error = "Cannot create env.txt";
  }
  ec.clear();
  s.folders = fs::is_directory(root / "source", ec) && !ec;
  ec.clear();
  s.folders = s.folders && fs::is_directory(game, ec) && !ec;
  ec.clear();
  s.folders = s.folders && fs::is_directory(root / "Diagnostics", ec) && !ec;
  s.xex = HasData(game / "default.xex");
  s.xexp = HasData(game / "default.xexp");
  ec.clear();
  s.update = fs::is_directory(game / "update", ec) && !ec;

  // Keep a phone-friendly transfer guide beside the status report. GoldHEN's
  // existing FTP service is the receiver; this utility does not open a new
  // network listener or modify the user's existing FTP configuration.
  const fs::path guide_path = root / "transfer-guide.txt";
  ec.clear();
  if (!fs::exists(guide_path, ec) && !ec) {
    std::ofstream guide(guide_path);
    if (guide) {
      guide << "GTA IV SETUP MANAGER - LOCAL TRANSFER GUIDE\\n"
            << "1. On PS4, enable GoldHEN FTP in GoldHEN settings.\\n"
            << "2. Note the PS4 LAN IP shown by the console network settings.\\n"
            << "3. On your Android phone, connect AndFTP to that IP, port 2121, "
               "protocol FTP (plain).\\n"
            << "4. Browse to /data/LibertyRecomp/game/ on the PS4.\\n"
            << "5. Upload only compatible game files you are authorized to use.\\n"
            << "6. Return here and choose SCAN AGAIN after the transfer finishes.\\n"
            << "Do not delete or overwrite existing files unless you have a backup.\\n";
    } else if (s.error.empty()) {
      s.error = "Cannot create transfer-guide.txt";
    }
  }

  std::ofstream status(root / "setup-status.txt", std::ios::trunc);
  if (status) {
    status << "GTA IV SETUP MANAGER\nLast scan: " << Now()
           << "\nFolders: " << (s.folders ? "READY" : "ERROR")
           << "\ndefault.xex: " << (s.xex ? "FOUND" : "MISSING")
           << "\ndefault.xexp: " << (s.xexp ? "FOUND" : "MISSING")
           << "\nupdate/: " << (s.update ? "FOUND" : "NOT DETECTED")
           << "\nDestination: " << game.string()
           << "\nUse compatible prepared game data you are authorized to use. "
              "The manager does not create substitute game binaries.\n";
  } else if (s.error.empty()) {
    s.error = "Cannot write setup-status.txt";
  }
  Log("scan folders=" + std::to_string(s.folders) +
      " xex=" + std::to_string(s.xex) + " xexp=" + std::to_string(s.xexp) +
      " update=" + std::to_string(s.update) +
      (s.error.empty() ? "" : " error=" + s.error));
  return s;
}

class SetupDialog final : public rex::ui::ImGuiDialog {
 public:
  SetupDialog(rex::ui::ImGuiDrawer* drawer, std::function<void()> quit)
      : ImGuiDialog(drawer), quit_(std::move(quit)), scan_(ScanFiles()) {}

 private:
  void OnDraw(ImGuiIO&) override {
    ImGui::SetNextWindowSize(ImVec2(820, 560), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("GTA IV SETUP MANAGER", nullptr,
                     ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize)) {
      ImGui::TextColored(ImVec4(.95f, .12f, .25f, 1), "GTA IV SETUP MANAGER");
      ImGui::SameLine();
      ImGui::TextDisabled("VERSION 1.02");
      ImGui::Separator();
      const bool ready = scan_.folders && scan_.xex && scan_.xexp;
      ImGui::TextColored(ready ? ImVec4(.25f, .9f, .5f, 1) : ImVec4(1, .3f, .35f, 1),
                         "%s", ready ? "GAME DATA READY" : "SETUP INCOMPLETE");
      ImGui::Spacing();
      ImGui::Text("FOLDER CHECK");
      ImGui::BulletText("source/: %s", scan_.folders ? "READY" : "ERROR");
      ImGui::BulletText("game/: %s", scan_.folders ? "READY" : "ERROR");
      ImGui::BulletText("Diagnostics/: %s", scan_.folders ? "READY" : "ERROR");
      ImGui::Spacing();
      ImGui::Text("GAME FILE CHECK");
      ImGui::BulletText("default.xex: %s", scan_.xex ? "FOUND" : "MISSING");
      ImGui::BulletText("default.xexp: %s", scan_.xexp ? "FOUND" : "MISSING");
      ImGui::BulletText("update/: %s", scan_.update ? "FOUND" : "NOT DETECTED");
      ImGui::Spacing();
      ImGui::Text("ANDROID TO PS4 TRANSFER");
      ImGui::BulletText("Receiver: GoldHEN FTP already running on your PS4");
      ImGui::BulletText("Port: 2121  |  Protocol: FTP (plain)");
      ImGui::TextWrapped("Destination: %s", (fs::path(kRoot) / "game").string().c_str());
      ImGui::TextWrapped("On Android, use AndFTP with your PS4 LAN IP and upload "
                         "your authorized prepared files to the destination above.");
      ImGui::TextWrapped("When upload finishes, select SCAN AGAIN to refresh the "
                         "file checks. Transfer guide: /data/LibertyRecomp/transfer-guide.txt");
      ImGui::TextDisabled("This manager does not download or generate copyrighted game data.");
      if (!scan_.error.empty())
        ImGui::TextColored(ImVec4(1, .3f, .35f, 1), "ERROR: %s", scan_.error.c_str());
      ImGui::Separator();
      if (ImGui::Button("SCAN AGAIN", ImVec2(180, 42))) {
        try { scan_ = ScanFiles(); }
        catch (const std::exception& e) {
          scan_.error = e.what();
          Log(std::string("rescan exception: ") + e.what());
        }
      }
      ImGui::SameLine();
      if (ImGui::Button("EXIT APP", ImVec2(120, 42)) && quit_) quit_();
    }
    ImGui::End();
  }
  std::function<void()> quit_;
  Scan scan_;
};

class SetupManagerApp final : public rex::ReXApp {
 public:
  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& context) {
    return std::unique_ptr<SetupManagerApp>(new SetupManagerApp(context));
  }
 private:
  explicit SetupManagerApp(rex::ui::WindowedAppContext& context)
      : ReXApp(context, "GTA IV Setup Manager", {}) {}

  // Use the SDK PS4 window/presenter and ImGui, but never create or launch
  // the GTA IV guest runtime from this separate utility.
  bool OnInitialize() override {
    return SetupEnvironment() && SetupPresentation();
  }
  void OnPreSetup(rex::RuntimeConfig& config) override {
    config.gpu_plugin = "xenos";
  }
  void OnCreateDialogs(rex::ui::ImGuiDrawer* drawer) override {
    new SetupDialog(drawer, [this] { app_context().QuitFromUIThread(); });
  }
};
}  // namespace

REX_DEFINE_APP(gtaiv_setup_manager, SetupManagerApp::Create)
