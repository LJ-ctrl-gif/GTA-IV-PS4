#include <SDL3/SDL.h>
#include <orbis/Sysmodule.h>
#include <orbis/UserService.h>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>
namespace fs = std::filesystem;
static constexpr const char* ROOT_PATH="/data/LibertyRecomp";
struct Scan { bool folders_ok=false, xex=false, xexp=false, update_dir=false; std::string error, report; };
static std::string stamp(){ std::time_t n=std::time(nullptr); char b[32]{}; std::tm* t=std::localtime(&n); if(t) std::strftime(b,sizeof(b),"%Y-%m-%d %H:%M:%S",t); return b; }
static void log_line(const std::string& message){
 std::error_code e; fs::create_directories(fs::path(ROOT_PATH)/"Diagnostics",e);
 std::ofstream l(fs::path(ROOT_PATH)/"Diagnostics"/"setup-manager.log",std::ios::app);
 if(l) l<<"["<<stamp()<<"] "<<message<<"\n";
}
static bool nonempty_file(const fs::path& p){ std::error_code e; return fs::is_regular_file(p,e)&&!e&&fs::file_size(p,e)>0&&!e; }
static Scan prepare_and_scan(){
 Scan s; const fs::path root=ROOT_PATH, game=root/"game", source=root/"source", diag=root/"Diagnostics"; std::error_code e;
 fs::create_directories(source,e); if(e) s.error="source folder: "+e.message();
 e.clear(); fs::create_directories(game,e); if(e&&s.error.empty()) s.error="game folder: "+e.message();
 e.clear(); fs::create_directories(diag,e); if(e&&s.error.empty()) s.error="Diagnostics folder: "+e.message();
 const fs::path env=root/"env.txt";
 e.clear(); const bool env_exists=fs::exists(env,e);
 if(!env_exists&&!e){ std::ofstream f(env); if(f) f<<"# Liberty Recompiled settings. Existing settings are never overwritten.\n"; }
 e.clear(); s.folders_ok=fs::is_directory(source,e)&&!e;
 e.clear(); s.folders_ok=s.folders_ok&&fs::is_directory(game,e)&&!e;
 e.clear(); s.folders_ok=s.folders_ok&&fs::is_directory(diag,e)&&!e;
 s.xex=nonempty_file(game/"default.xex"); s.xexp=nonempty_file(game/"default.xexp");
 e.clear(); s.update_dir=fs::is_directory(game/"update",e)&&!e;
 std::ostringstream o; o<<"GTA IV SETUP MANAGER\nLast scan: "<<stamp()<<"\n";
 o<<"Folders: "<<(s.folders_ok?"READY":"ERROR")<<"\ndefault.xex: "<<(s.xex?"FOUND":"MISSING")<<"\ndefault.xexp: "<<(s.xexp?"FOUND":"MISSING");
 o<<"\nupdate/: "<<(s.update_dir?"FOUND":"NOT DETECTED")<<"\nGame data: "<<((s.xex&&s.xexp)?"READY":"WAITING FOR FILES");
 if(!s.error.empty()) o<<"\nError: "<<s.error;
 o<<"\n\nExpected destination: "<<game.string()<<"\nUpload the complete prepared folder contents here. Do not create dummy game files.\n"; s.report=o.str();
 std::ofstream status(root/"setup-status.txt",std::ios::trunc); if(status) status<<s.report;
 log_line("scan: folders="+std::to_string(s.folders_ok)+" default.xex="+std::to_string(s.xex)+" default.xexp="+std::to_string(s.xexp)+" update_dir="+std::to_string(s.update_dir)+(s.error.empty()?"":" error="+s.error));
 return s;
}
static void color(SDL_Renderer*r,Uint8 a,Uint8 b,Uint8 c){SDL_SetRenderDrawColor(r,a,b,c,255);}
static void rect(SDL_Renderer*r,float x,float y,float w,float h,Uint8 a,Uint8 b,Uint8 c){SDL_FRect q{x,y,w,h};color(r,a,b,c);SDL_RenderFillRect(r,&q);}
static void frame(SDL_Renderer*r,float x,float y,float w,float h){SDL_FRect q{x,y,w,h};color(r,125,24,42);SDL_RenderRect(r,&q);}
static void label(SDL_Renderer*r,float x,float y,const std::string&v,Uint8 a=225,Uint8 b=225,Uint8 c=230){color(r,a,b,c);SDL_RenderDebugText(r,x,y,v.c_str());}
static void draw(SDL_Renderer*r,const Scan&s){
 color(r,7,8,12);SDL_RenderClear(r);rect(r,0,0,960,58,18,10,14);rect(r,0,56,960,2,190,25,55);
 label(r,32,22,"GTA IV SETUP MANAGER",255,65,92);label(r,760,22,"VERSION 1.01",155,155,165);
 rect(r,32,88,896,100,16,19,27);frame(r,32,88,896,100);
 bool ready=s.xex&&s.xexp;label(r,56,112,ready?"GAME DATA READY":"SETUP INCOMPLETE",ready?100:255,ready?235:90,ready?150:105);
 label(r,56,145,ready?"Required game files were detected.":"Folders are ready. Transfer your prepared game files to continue.");
 rect(r,32,210,896,198,16,19,27);frame(r,32,210,896,198);label(r,56,232,"FILE CHECK",255,65,92);
 label(r,56,270,std::string("Folders:       ")+(s.folders_ok?"READY":"ERROR"),s.folders_ok?110:255,s.folders_ok?230:90,s.folders_ok?155:100);
 label(r,56,300,std::string("default.xex:   ")+(s.xex?"FOUND":"MISSING"),s.xex?110:255,s.xex?230:90,s.xex?155:100);
 label(r,56,330,std::string("default.xexp:  ")+(s.xexp?"FOUND":"MISSING"),s.xexp?110:255,s.xexp?230:90,s.xexp?155:100);
 label(r,56,360,std::string("update/:       ")+(s.update_dir?"FOUND":"NOT DETECTED"),190,190,200);
 rect(r,32,430,896,68,16,19,27);frame(r,32,430,896,68);label(r,56,450,"FTP DESTINATION",255,65,92);label(r,56,475,"/data/LibertyRecomp/game/");
 label(r,40,520,"CROSS: SCAN AGAIN     CIRCLE: EXIT",180,180,190);
 if(!s.error.empty()) label(r,500,520,"SETUP ERROR - SEE setup-manager.log",255,90,100);
 SDL_RenderPresent(r);
}
static int run_app(){
 Scan s;
 try { s=prepare_and_scan(); }
 catch(const std::exception& e){ log_line(std::string("filesystem startup exception: ")+e.what()); s.error=e.what(); }
 if(!SDL_Init(SDL_INIT_VIDEO)){ log_line(std::string("SDL video initialization failed: ")+SDL_GetError()); return 2; }
 // Gamepad support is optional: failure must not prevent the setup screen opening.
 if(!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) log_line(std::string("gamepad initialization unavailable: ")+SDL_GetError());
 SDL_Window*w=SDL_CreateWindow("GTA IV Setup Manager",1920,1080,SDL_WINDOW_FULLSCREEN);
 if(!w){ log_line(std::string("SDL_CreateWindow failed: ")+SDL_GetError()); SDL_Quit(); return 3; }
 SDL_Renderer*r=SDL_CreateRenderer(w,nullptr);
 if(!r){ log_line(std::string("SDL_CreateRenderer failed: ")+SDL_GetError()); SDL_DestroyWindow(w); SDL_Quit(); return 4; }
 SDL_SetRenderScale(r,2.0f,2.0f); bool running=true;
 while(running){ SDL_Event e; while(SDL_PollEvent(&e)){
  if(e.type==SDL_EVENT_QUIT) running=false;
  if(e.type==SDL_EVENT_KEY_DOWN){ if(e.key.key==SDLK_ESCAPE) running=false; if(e.key.key==SDLK_RETURN||e.key.key==SDLK_SPACE){ try{s=prepare_and_scan();}catch(const std::exception& ex){s.error=ex.what();log_line(std::string("rescan exception: ")+ex.what());} } }
  if(e.type==SDL_EVENT_GAMEPAD_BUTTON_DOWN){ if(e.gbutton.button==SDL_GAMEPAD_BUTTON_EAST) running=false; if(e.gbutton.button==SDL_GAMEPAD_BUTTON_SOUTH){ try{s=prepare_and_scan();}catch(const std::exception& ex){s.error=ex.what();log_line(std::string("rescan exception: ")+ex.what());} } }
 } draw(r,s); SDL_Delay(50); }
 SDL_DestroyRenderer(r); SDL_DestroyWindow(w); SDL_Quit(); return 0;
}
int main(int,char**){
 const OrbisSysModuleInternal modules[]={ORBIS_SYSMODULE_INTERNAL_SYSTEM_SERVICE,ORBIS_SYSMODULE_INTERNAL_USER_SERVICE,ORBIS_SYSMODULE_INTERNAL_VIDEO_OUT,ORBIS_SYSMODULE_INTERNAL_AUDIOOUT,ORBIS_SYSMODULE_INTERNAL_PAD,ORBIS_SYSMODULE_INTERNAL_NET};
 for(auto module:modules){ const int rc=sceSysmoduleLoadModuleInternal(module); if(rc<0) log_line("optional system module load returned "+std::to_string(rc)); }
 OrbisUserServiceInitializeParams user_params={}; user_params.priority=256;
 const int user_rc=sceUserServiceInitialize(&user_params);
 if(user_rc<0) log_line("user service initialization returned "+std::to_string(user_rc));
 // SDL video initialization stays on the PS4 process main thread.
 return run_app();
}
