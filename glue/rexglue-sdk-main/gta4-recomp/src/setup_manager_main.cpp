#include <SDL3/SDL.h>
#include <chrono>
#include <cstddef>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <system_error>
namespace fs = std::filesystem;
static const fs::path ROOT="/data/LibertyRecomp", GAME=ROOT/"game", SOURCE=ROOT/"source", DIAG=ROOT/"Diagnostics";
struct Scan { bool folders_ok=false, xex=false, xexp=false, update_dir=false; std::string error, report; };
static std::string stamp(){ std::time_t n=std::time(nullptr); char b[32]{}; std::tm* t=std::localtime(&n); if(t) std::strftime(b,sizeof(b),"%Y-%m-%d %H:%M:%S",t); return b; }
static bool nonempty_file(const fs::path& p){ std::error_code e; return fs::is_regular_file(p,e)&&!e&&fs::file_size(p,e)>0&&!e; }
static Scan prepare_and_scan(){
 Scan s; std::error_code e;
 fs::create_directories(SOURCE,e); if(e) s.error="source folder: "+e.message();
 e.clear(); fs::create_directories(GAME,e); if(e&&s.error.empty()) s.error="game folder: "+e.message();
 e.clear(); fs::create_directories(DIAG,e); if(e&&s.error.empty()) s.error="Diagnostics folder: "+e.message();
 const fs::path env=ROOT/"env.txt";
 if(!fs::exists(env,e)&&!e){ std::ofstream f(env); if(f) f<<"# Liberty Recompiled settings. Existing settings are never overwritten.\n"; }
 s.folders_ok=fs::is_directory(SOURCE)&&fs::is_directory(GAME)&&fs::is_directory(DIAG);
 s.xex=nonempty_file(GAME/"default.xex"); s.xexp=nonempty_file(GAME/"default.xexp"); s.update_dir=fs::is_directory(GAME/"update");
 std::ostringstream o; o<<"GTA IV SETUP MANAGER\nLast scan: "<<stamp()<<"\n";
 o<<"Folders: "<<(s.folders_ok?"READY":"ERROR")<<"\ndefault.xex: "<<(s.xex?"FOUND":"MISSING")<<"\ndefault.xexp: "<<(s.xexp?"FOUND":"MISSING");
 o<<"\nupdate/: "<<(s.update_dir?"FOUND":"NOT DETECTED")<<"\nGame data: "<<((s.xex&&s.xexp)?"READY":"WAITING FOR FILES");
 if(!s.error.empty()) o<<"\nError: "<<s.error;
 o<<"\n\nExpected destination: "<<GAME.string()<<"\nUpload the complete prepared folder contents here. Do not create dummy game files.\n"; s.report=o.str();
 std::ofstream status(ROOT/"setup-status.txt",std::ios::trunc); if(status) status<<s.report;
 std::ofstream log(DIAG/"setup-manager.log",std::ios::app);
 if(log) log<<"["<<stamp()<<"] scan: folders="<<s.folders_ok<<" default.xex="<<s.xex<<" default.xexp="<<s.xexp<<" update_dir="<<s.update_dir<<(s.error.empty()?"":" error="+s.error)<<"\n";
 return s;
}
static void color(SDL_Renderer*r,Uint8 a,Uint8 b,Uint8 c){SDL_SetRenderDrawColor(r,a,b,c,255);}
static void rect(SDL_Renderer*r,float x,float y,float w,float h,Uint8 a,Uint8 b,Uint8 c){SDL_FRect q{x,y,w,h};color(r,a,b,c);SDL_RenderFillRect(r,&q);}
static void frame(SDL_Renderer*r,float x,float y,float w,float h){SDL_FRect q{x,y,w,h};color(r,125,24,42);SDL_RenderRect(r,&q);}
static void label(SDL_Renderer*r,float x,float y,const std::string&v,Uint8 a=225,Uint8 b=225,Uint8 c=230){color(r,a,b,c);SDL_RenderDebugText(r,x,y,v.c_str());}
static void draw(SDL_Renderer*r,const Scan&s){
 color(r,7,8,12);SDL_RenderClear(r);rect(r,0,0,960,58,18,10,14);rect(r,0,56,960,2,190,25,55);
 label(r,32,22,"GTA IV SETUP MANAGER",255,65,92);label(r,760,22,"VERSION 1.00",155,155,165);
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
 Scan s=prepare_and_scan();
 if(!SDL_Init(SDL_INIT_VIDEO|SDL_INIT_GAMEPAD)){std::ofstream l(DIAG/"setup-manager.log",std::ios::app);if(l)l<<"["<<stamp()<<"] SDL_Init failed: "<<SDL_GetError()<<"\n";return 2;}
 SDL_Window*w=SDL_CreateWindow("GTA IV Setup Manager",1920,1080,SDL_WINDOW_FULLSCREEN);
 if(!w){std::ofstream l(DIAG/"setup-manager.log",std::ios::app);if(l)l<<"["<<stamp()<<"] SDL_CreateWindow failed: "<<SDL_GetError()<<"\n";SDL_Quit();return 3;}
 SDL_Renderer*r=SDL_CreateRenderer(w,nullptr);
 if(!r){std::ofstream l(DIAG/"setup-manager.log",std::ios::app);if(l)l<<"["<<stamp()<<"] SDL_CreateRenderer failed: "<<SDL_GetError()<<"\n";SDL_DestroyWindow(w);SDL_Quit();return 4;}
 SDL_SetRenderScale(r,2.0f,2.0f); bool running=true;
 while(running){SDL_Event e;while(SDL_PollEvent(&e)){
  if(e.type==SDL_EVENT_QUIT)running=false;
  if(e.type==SDL_EVENT_KEY_DOWN){if(e.key.key==SDLK_ESCAPE)running=false;if(e.key.key==SDLK_RETURN||e.key.key==SDLK_SPACE)s=prepare_and_scan();}
  if(e.type==SDL_EVENT_GAMEPAD_BUTTON_DOWN){if(e.gbutton.button==SDL_GAMEPAD_BUTTON_EAST)running=false;if(e.gbutton.button==SDL_GAMEPAD_BUTTON_SOUTH)s=prepare_and_scan();}
 } draw(r,s);SDL_Delay(50);}
 SDL_DestroyRenderer(r);SDL_DestroyWindow(w);SDL_Quit();return 0;
}
extern "C" int user_malloc_init(void);
extern "C" int user_malloc_finalize(void);
extern "C" int ps4_main(size_t,const void*){if(user_malloc_init()!=0)return 1;int result=run_app();user_malloc_finalize();return result;}
