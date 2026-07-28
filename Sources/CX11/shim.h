#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/extensions/scrnsaver.h>
#include <X11/extensions/Xrandr.h>

// Xlib exposes most of its vocabulary as preprocessor macros, which Swift cannot
// see. Re-expose the handful Blink needs as real constants.
static const unsigned long blink_CWBackPixel       = CWBackPixel;
static const unsigned long blink_CWOverrideRedirect = CWOverrideRedirect;
static const unsigned long blink_CWEventMask       = CWEventMask;
static const unsigned long blink_CWSaveUnder       = CWSaveUnder;

static const long blink_ExposureMask        = ExposureMask;
static const long blink_KeyPressMask        = KeyPressMask;
static const long blink_ButtonPressMask     = ButtonPressMask;
static const long blink_StructureNotifyMask = StructureNotifyMask;
static const long blink_VisibilityChangeMask = VisibilityChangeMask;

static const int blink_InputOutput   = InputOutput;
static const int blink_CopyFromParent = CopyFromParent;
static const int blink_GrabModeAsync = GrabModeAsync;
static const int blink_KeyPress      = KeyPress;
static const int blink_Expose        = Expose;
static const int blink_VisibilityNotify = VisibilityNotify;
static const unsigned long blink_CurrentTime = CurrentTime;
static const unsigned long blink_None = None;

static const unsigned long blink_XK_Escape = XK_Escape;
static const unsigned long blink_XK_p      = XK_p;
static const unsigned long blink_XK_P      = XK_P;
