import kilo;

import std.stdio : writeln;
import std.format : sformat;
import std;

alias libc = core.stdc;

string LC(string name)() {
    return "import core.stdc." ~ name;
}

mixin(LC!"stdio : perror, snprintf, sscanf, FILE, fopen;");
mixin(LC!"stdlib : malloc, free, realloc, exit, atexit;");
mixin(LC!"errno : errno, ENOTTY, ENOENT;");
mixin(LC!"time : time;");
mixin(LC!"string : memcpy, memmove, memset, strlen, strerror, strstr, strchr, memcmp;");
mixin(LC!"signal : signal;");
mixin(LC!"config : c_long, c_ulong;");

enum SIGWINCH = 28;

// only stdio.h function not found in core.stdc
extern (C) cbuiltin.ssize_t getline(char** lineptr, size_t* n,
    FILE* stream);

// re-implementing some ctype.h functions, since they are small.
// code copied form jart/cosmopolitan/libc

int isspace(int c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' ||
        c == '\v';
}

int isprint(int c)
{
    return 0x20 <= c && c <= 0x7E;
}

int isdigit(int c)
{
    return '0' <= c && c <= '9';
}

alias dstderr = std.stdio.stderr;
/* making clear that kilo namespace is used
 to resolve conflicts between symbols built in C
  and D's reimport of those symbols in core.* */
alias cbuiltin = kilo;

/*Process events arriving from the standard input, which is,
* the user  is typing stuff on the terminal. */
enum KILO_QUIT_TIMES = 3;

/*When the file is modified, requires Ctrl-q to be
* pressed N times before actually quitting. */
void editorProcessKeypress(int fd)
{
    static quit_times = KILO_QUIT_TIMES;
    int c = editorReadKey(fd);
    switch (c)
    {
    case ENTER: /* Enter */
        editorInsertNewline();
        break;
    case CTRL_C: /* Ctrl-c */
        /* We ignore ctrl-c, it can't be so simple to lose the changes
         * to the edited file. */
        break;
    case CTRL_Q: /* Ctrl-q */
        /* Quit if the file was already saved. */
        if (ED.dirty && quit_times)
        {
            editorSetStatusMessage("WARNING!!! File has unsaved changes."
                    ~ "Press Ctrl-Q %s more times to quit.", quit_times);
            quit_times--;
            return;
        }
        exit(0);
        break;
    case CTRL_S: /* Ctrl-s */
        editorSave();
        break;
    case CTRL_F:
        editorFind(fd);
        break;
    case BACKSPACE, CTRL_H, DEL_KEY:
        editorDelChar();
        break;
    case PAGE_UP, PAGE_DOWN:
        if (c == PAGE_UP && ED.cy != 0)
            ED.cy = 0;
        else if (c == PAGE_DOWN && ED.cy != ED.screenrows - 1)
            ED.cy = ED.screenrows - 1;
        {
            int times = ED.screenrows;
            while (times--)
                editorMoveCursor(c == PAGE_UP ? ARROW_UP : ARROW_DOWN);
        }
        break;
    case ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT:
        editorMoveCursor(c);
        break;
    case CTRL_L: /* ctrl+l, clear screen */
        /* Just refresht the line as side effect. */
        break;
    case ESC:
        /* Nothing to do for ESC in this mode. */
        break;
    default:
        editorInsertChar(c);
        break;
    }

    quit_times = KILO_QUIT_TIMES; /* Reset it to the original value. */
}

enum ABUF_INIT = abuf(null, 0);
/* This function writes the whole screen using VT100 escape characters
 * starting from the logical state of the editor in the global state 'E'. */

// extern(C) because it is used by kilo.c still.
extern (C) void editorRefreshScreen()
{
    int y;
    erow* r;
    char[32] buf = void;
    // TODO: replace abuf with a D array.
    abuf ab = ABUF_INIT;

    abAppend(&ab, "\x1b[?25l", 6); /* Hide cursor. */
    abAppend(&ab, "\x1b[H", 3); /* Go home. */
    for (y = 0; y < ED.screenrows; y++)
    {
        int filerow = ED.rowoff + y;

        if (filerow >= ED.numrows)
        {
            if (ED.numrows == 0 && y == ED.screenrows / 3)
            {
                char[80] welcome = void;
                int welcomelen = snprintf(welcome.ptr, welcome.length,
                    "Dilo editor -- verison %s\x1b[0K\r\n", DILO_VERSION.ptr);
                int padding = (ED.screencols - welcomelen) / 2;
                if (padding)
                {
                    abAppend(&ab, "~", 1);
                    padding--;
                }
                while (padding--)
                    abAppend(&ab, " ", 1);
                abAppend(&ab, welcome.ptr, welcomelen);
            }
            else
            {
                abAppend(&ab, "~\x1b[0K\r\n", 7);
            }
            continue;
        }

        r = &ED.row[filerow];

        int len = r.rsize - ED.coloff;
        int current_color = -1;
        if (len > 0)
        {
            if (len > ED.screencols)
                len = ED.screencols;
            char* c = r.render + ED.coloff;
            ubyte* hl = r.hl + ED.coloff;
            int j;
            for (j = 0; j < len; j++)
            {
                if (hl[j] == HL_NONPRINT)
                {
                    char sym;
                    abAppend(&ab, "\x1b[7m", 4);
                    if (c[j] <= 26)
                        sym = cast(char)('@' + c[j]);
                    else
                        sym = '?';
                    abAppend(&ab, &sym, 1);
                    abAppend(&ab, "\x1b[0m", 4);
                }
                else if (hl[j] == HL_NORMAL)
                {
                    if (current_color != -1)
                    {
                        abAppend(&ab, "\x1b[39m", 5);
                        current_color = -1;
                    }
                    abAppend(&ab, c + j, 1);
                }
                else
                {
                    int color = editorSyntaxToColor(hl[j]);
                    if (color != current_color)
                    {
                        char[16] _buf = void;
                        int clen = snprintf(_buf.ptr, _buf.length, "\x1b[%dm", color);
                        current_color = color;
                        abAppend(&ab, _buf.ptr, clen);
                    }
                    abAppend(&ab, c + j, 1);
                }
            }
        }
        abAppend(&ab, "\x1b[39m", 5);
        abAppend(&ab, "\x1b[0K", 4);
        abAppend(&ab, "\r\n", 2);
    }

    /* Create a two rows status. First row: */
    abAppend(&ab, "\x1b[0K", 4);
    abAppend(&ab, "\x1b[7m", 4);
    char[80] status = void;
    char[80] rstatus = void;
    int len = snprintf(status.ptr, status.length, "%.20s - %d lines %s",
        ED.filename, ED.numrows, ED.dirty ? "(modified)".ptr : "".ptr);
    int rlen = snprintf(rstatus.ptr, rstatus.length,
        "%d/%d", ED.rowoff + ED.cy + 1, ED.numrows);
    if (len > ED.screencols)
        len = ED.screencols;
    abAppend(&ab, status.ptr, len);
    while (len < ED.screencols)
    {
        if (ED.screencols - len == rlen)
        {
            abAppend(&ab, rstatus.ptr, rlen);
            break;
        }
        else
        {
            abAppend(&ab, " ", 1);
            len++;
        }
    }
    abAppend(&ab, "\x1b[0m\r\n", 6);

    /* Second row depends on E.statusmsg and the status message update time. */
    abAppend(&ab, "\x1b[0K", 4);
    size_t msglen = strlen(ED.statusmsg.ptr);
    if (msglen && time(null) - ED.statusmsg_time < 5)
        abAppend(&ab, ED.statusmsg.ptr, msglen <= ED.screencols ? cast(int) msglen : ED.screencols);

    /* Put cursor at its current position. Note that the horizontal position
     * at which the cursor is displayed may be different compared to 'E.cx'
     * because of TABs. */
    int j;
    int cx = 1;
    int filerow = ED.rowoff + ED.cy;
    erow* row = (filerow >= ED.numrows) ? null : &ED.row[filerow];
    if (row)
    {
        for (j = ED.coloff; j < (ED.cx + ED.coloff); j++)
        {
            if (j < row.size && row.chars[j] == TAB)
                cx += 7 - ((cx) % 8);
            cx++;
        }
    }
    snprintf(buf.ptr, buf.length, "\x1b[%d;%dH", ED.cy + 1, cx);
    abAppend(&ab, buf.ptr, cast(int) strlen(buf.ptr));
    abAppend(&ab, "\x1b[?25h", 6); /* Show cursor. */
    cbuiltin.write(STDOUT_FILENO, ab.b, ab.len);
    abFree(&ab);
}
/*Set an editor status message for the second line
  of the status, at the end of the screen.
*/
void editorSetStatusMessage(Ts...)(const char[] fmt, Ts values)
{
    //char[80] buf = E.statusmsg;
    sformat(ED.statusmsg, fmt, values);
    ED.statusmsg_time = time(null);
}

// dmd is not able to set errno since
// it's a macro, made a wrapper function in C.
import dilo_errno : setErrno;

int enableRawMode(int fd)
{
    /* Raw mode: 1960 magic shit. */
    termios raw;
    if (ED.rawmode)
        return 0;
    bool err = true;
    // replaced 'goto fatal' with scope(exit)
    scope (exit)
        if (err)
            setErrno(ENOTTY);

    if (!isatty(STDIN_FILENO))
        return -1;

    atexit(&editorAtExit);
    if (tcgetattr(fd, &orig_termios) == -1)
        return -1;
    raw = orig_termios; /* modify the original mode */
    /* input modes: no break, no CR to NL, no parity check, no strip char,
     * no start/stop output control. */
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    /* output modes - disable post processing */
    raw.c_oflag &= ~(OPOST);
    /* control modes - set 8 bit chars */
    raw.c_cflag |= (CS8);
    /* local modes - choing off, canonical off, no extended functions,
     * no signal chars (^Z,^C) */
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    /* control chars - set return condition: min number of bytes and timer. */
    raw.c_cc[VMIN] = 0; /* Return each byte, or zero for timeout. */
    raw.c_cc[VTIME] = 1; /* 100 ms timeout (unit is tens of second). */

    /* put terminal in raw mode after flushing */
    if (tcsetattr(fd, TCSAFLUSH, &raw) < 0)
        return -1;

    ED.rawmode = 1;
    // no error, set to false so that scope(exit)
    // dont modify errno
    err = false;
    return 0;
}

/* Load the specified program in the editor memory and returns 0 on success
 * or 1 on error. */
int editorOpen(string filename)
{
    FILE* fp;
    filename ~= '\0'; // alloc new string
    ED.dirty = 0;
    free(ED.filename);
    size_t fnlen = strlen(filename.ptr) + 1;
    ED.filename = cast(char*) malloc(fnlen);
    memcpy(ED.filename, filename.ptr, fnlen);

    fp = fopen(filename.ptr, "r");
    if (!fp)
    {
        if (errno != ENOENT)
        {
            perror("Opening file");
            exit(1);
        }
        return 1;
    }

    char* line = null;
    size_t linecap = 0;
    cbuiltin.ssize_t linelen;
    while ((linelen = getline(&line, &linecap, fp)) != -1)
    {
        if (linelen && (line[linelen - 1] == '\n' || line[linelen - 1] == '\r'))
            line[--linelen] = '\0';
        editorInsertRow(ED.numrows, line, linelen);
    }
    free(line);
    fclose(fp);
    ED.dirty = 0;
    return 0;
}

/* Select the syntax highlight scheme depending on the filename,
 * setting it in the global state E.syntax. */
void editorSelectSyntaxHighlight(string filename)
{
    // allocs new string
    filename ~= '\0';
    foreach (size_t j; 0 .. HLDB_ENTRIES)
    {
        editorSyntax* s = &HLDB[j];
        for (size_t i = 0; s.filematch[i] != null; i++)
        {
            char* p;
            size_t patlen = strlen(s.filematch[i]);
            // cast away the const, okay since strstr only modifies
            // the pointer, not the chars
            if ((p = strstr(cast(char*) filename.ptr, s.filematch[i])) != NULL)
            {
                if (s.filematch[i][0] != '.' || p[patlen] == '\0')
                {
                    ED.syntax = s;
                    return;
                }
            }
        }
    }
}

enum DILO_VERSION = "0.0.1";

/* Syntax highlight types */
enum HL_NORMAL = 0;
enum HL_NONPRINT = 1;
enum HL_COMMENT = 2; /* Single line comment. */
enum HL_MLCOMMENT = 3; /* Multi-line comment. */
enum HL_KEYWORD1 = 4;
enum HL_KEYWORD2 = 5;
enum HL_STRING = 6;
enum HL_NUMBER = 7;
enum HL_MATCH = 8; /* Search match. */

enum HL_HIGHLIGHT_STRINGS = 1 << 0;
enum HL_HIGHLIGHT_NUMBERS = 1 << 1;

struct editorSyntax
{
    char** filematch;
    char** keywords;
    char[2] singleline_comment_start;
    char[3] multiline_comment_start;
    char[3] multiline_comment_end;
    int flags;
}

/* This structure represents a single line of the file we are editing. */
struct erow
{
    int idx; /* Row index in the file, zero-based. */
    int size; /* Size of the row, excluding the null term. */
    int rsize; /* Size of the rendered row. */
    char* chars; /* Row content. */
    char* render; /* Row content "rendered" for screen (for TABs). */
    ubyte* hl; /* Syntax highlight type for each character in render.*/
    int hl_oc; /* Row had open comment at end in last syntax highlight
                           check. */
}

struct hlcolor
{
    int r, g, b;
}

struct editorConfig
{
    int cx, cy; /* Cursor x and y position in characters */
    int rowoff; /* Offset of row displayed. */
    int coloff; /* Offset of column displayed. */
    int screenrows; /* Number of rows that we can show */
    int screencols; /* Number of cols that we can show */
    int numrows; /* Number of rows */
    int rawmode; /* Is terminal raw mode enabled? */
    erow* row; /* Rows */
    int dirty; /* File modified but not saved. */
    char* filename; /* Currently open filename */
    char[80] statusmsg;
    cbuiltin.time_t statusmsg_time;
    editorSyntax* syntax; /* Current syntax highlight, or NULL. */
}

private editorConfig ED;

// TODO: convert back to a proper enum
// original code treats KEY_ACTION as just ints
// wich is why it is so hard to translate

// enum KEY_ACTION {...} 
enum int KEY_NULL = 0, /* NULL */
    CTRL_C = 3, /* Ctrl-c */
    CTRL_D = 4, /* Ctrl-d */
    CTRL_F = 6, /* Ctrl-f */
    CTRL_H = 8, /* Ctrl-h */
    TAB = 9, /* Tab */
    CTRL_L = 12, /* Ctrl+l */
    ENTER = 13, /* Enter */
    CTRL_Q = 17, /* Ctrl-q */
    CTRL_S = 19, /* Ctrl-s */
    CTRL_U = 21, /* Ctrl-u */
    ESC = 27, /* Escape */
    BACKSPACE = 127, /* Backspace */
    /* The following are just soft codes, not really reported by the
         * terminal directly. */
    ARROW_LEFT = 1000,
    ARROW_RIGHT = 1001,
    ARROW_UP = 1002,
    ARROW_DOWN = 1003,
    DEL_KEY = 1004,
    HOME_KEY = 1005,
    END_KEY = 1006,
    PAGE_UP = 1007,
    PAGE_DOWN = 1008;

/* =========================== Syntax highlights DB =========================
 *
 * In order to add a new syntax, define two arrays with a list of file name
 * matches and keywords. The file name matches are used in order to match
 * a given syntax with a given file name: if a match pattern starts with a
 * dot, it is matched as the last past of the filename, for example ".c".
 * Otherwise the pattern is just searched inside the filenme, like "Makefile").
 *
 * The list of keywords to highlight is just a list of words, however if they
 * a trailing '|' character is added at the end, they are highlighted in
 * a different color, so that you can have two different sets of keywords.
 *
 * Finally add a stanza in the HLDB global variable with two two arrays
 * of strings, and a set of flags in order to enable highlighting of
 * comments and numbers.
 *
 * The characters for single and multi line comments must be exactly two
 * and must be provided as well (see the C language example).
 *
 * There is no support to highlight patterns currently. */

// TODO: remove this hack this hack that converts strings to char*

/* C / C++ */
__gshared char*[6] C_HL_extensions;
__gshared string[6] extNames = [".c", ".h", ".cpp", ".hpp", ".cc", null];

void initC_HL_extensions()
{
    foreach (i; 0 .. 6 - 1)
    {

        extNames[i] ~= '\0';
        C_HL_extensions[i] = extNames[i].dup.ptr;
    }
    C_HL_extensions[6 - 1] = null;
}

__gshared char*[82] C_HL_keywords;
__gshared string[82] keyNames = [
    /* C Keywords */
    "auto", "break", "case", "continue", "default", "do", "else", "enum",
    "extern", "for", "goto", "if", "register", "return", "sizeof", "static",
    "struct", "switch", "typedef", "union", "volatile", "while", "NULL",

    /* C++ Keywords */
    "alignas", "alignof", "and", "and_eq", "asm", "bitand", "bitor", "class",
    "compl", "constexpr", "const_cast", "deltype", "delete", "dynamic_cast",
    "explicit", "export", "false", "friend", "inline", "mutable", "namespace",
    "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq",
    "private", "protected", "public", "reinterpret_cast", "static_assert",
    "static_cast", "template", "this", "thread_local", "throw", "true", "try",
    "typeid", "typename", "virtual", "xor", "xor_eq",

    /* C types */
    "int|", "long|", "double|", "float|", "char|", "unsigned|", "signed|",
    "void|", "short|", "auto|", "const|", "bool|", null
];

void initC_HL_keywords()
{
    foreach (i; 0 .. 82 - 1)
    {

        keyNames[i] ~= '\0';
        C_HL_keywords[i] = keyNames[i].dup.ptr;
    }
    C_HL_keywords[82 - 1] = null;
}

void initGlobals()
{
    initC_HL_extensions();
    initC_HL_keywords();
}

/*Here we define an array of syntax highlights by extensions, keywords,
 *comments delimiters and flags. */
editorSyntax[1] HLDB = [
    editorSyntax(
        /* C / C++ */
        C_HL_extensions.ptr, // [6]
        C_HL_keywords.ptr, // [82]
        "//", "/*", "*/",
        HL_HIGHLIGHT_STRINGS | HL_HIGHLIGHT_NUMBERS
    )
];

enum HLDB_ENTRIES = HLDB.length;
/* ======================= Low level terminal handling ====================== */

termios orig_termios; /* In order to restore at exit.*/

void disableRawMode(int fd)
{
    /* Don't even check the return value as it's too late. */
    if (ED.rawmode)
    {
        tcsetattr(fd, TCSAFLUSH, &orig_termios);
        ED.rawmode = 0;
    }
}

/* Called at exit to avoid remaining in raw mode. */
//extern because it is passed to libc function atexit
extern (C) void editorAtExit()
{
    disableRawMode(STDIN_FILENO);
}

/* Read a key from the terminal put in raw mode, trying to handle
 * escape sequences. */
int editorReadKey(int fd)
{
    long nread;
    char c;
    char[3] seq;
    while ((nread = read(fd, &c, 1)) == 0)
        if (nread == -1)
            exit(1);
    while (true)
    {
        switch (c)
        {
        case cast(char) ESC: /* escape sequence */
            /* If this is just an ESC, we'll timeout here. */
            if (cbuiltin.read(fd, seq.ptr, 1) == 0)
                return ESC;
            // TODO: remove pointer arithemetic
            if (cbuiltin.read(fd, seq.ptr + 1, 1) == 0)
                return ESC;
            /* ESC [ sequences. */
            if (seq[0] == '[')
            {
                if (seq[1] >= '0' && seq[1] <= '9')
                {
                    /* Extended escape, read additional byte. */
                    // TODO: removee pointer arithemetic
                    if (read(fd, seq.ptr + 2, 1) == 0)
                        return ESC;
                    if (seq[2] == '~')
                    {
                        switch (seq[1])
                        {
                        case '3':
                            return DEL_KEY;
                        case '5':
                            return PAGE_UP;
                        case '6':
                            return PAGE_DOWN;
                        default:
                            writeln(dstderr, "unreacheable default case in", __LINE__);
                            exit(1);
                        }
                    }
                }
                else
                {
                    switch (seq[1])
                    {
                    case 'A':
                        return ARROW_UP;
                    case 'B':
                        return ARROW_DOWN;
                    case 'C':
                        return ARROW_RIGHT;
                    case 'D':
                        return ARROW_LEFT;
                    case 'H':
                        return HOME_KEY;
                    case 'F':
                        return END_KEY;
                    default:
                        writeln(dstderr, "unreacheable default case in", __LINE__);
                        exit(1);
                    }
                }
            }
            /* ESC O sequences. */
            else if (seq[0] == 'O')
            {
                switch (seq[1])
                {
                case 'H':
                    return HOME_KEY;
                case 'F':
                    return END_KEY;
                default:
                    writeln(dstderr, "unreacheable default case in", __LINE__);
                    assert(0);
                }
            }
            break;
        default:
            return c;
        }
    }
}

/* Use the ESC [6n escape sequence to query the horizontal cursor position
 * and return it. On error -1 is returned, on success the position of the
 * cursor is stored at *rows and *cols and 0 is returned. */
int getCursorPosition(int ifd, int ofd, int* rows, int* cols)
{
    char[32] buf = void;
    uint i;

    /* Report cursor location */
    if (cbuiltin.write(ofd, "\x1b[6n".ptr, 4) != 4)
        return -1;

    /* Read the response: ESC [ rows ; cols R */
    while (i < buf.length - 1)
    {
        // TODO: remove pointer arithemetic
        if (read(ifd, buf.ptr + i, 1) != 1)
            break;
        if (buf[i] == 'R')
            break;
        i++;
    }
    buf[i] = '\0';

    /* Parse it. */
    if (buf[0] != ESC || buf[1] != '[')
        return -1;
    // TODO: remove pointer arithemetic
    if (sscanf(buf.ptr + 2, "%d;%d", rows, cols) != 2)
        return -1;
    return 0;
}

/* ====================== Syntax highlight color scheme  ==================== */

int is_separator(int c)
{
    return c == '\0' || isspace(c) || strchr(",.()+-/*=~%[];", c) != null;
}

/* Return true if the specified row last char is part of a multi line comment
 * that starts at this row or at one before, and does not end at the end
 * of the row but spawns to the next row. */
int editorRowHasOpenComment(erow* row)
{
    if (row.hl && row.rsize && row.hl[row.rsize - 1] == HL_MLCOMMENT &&
        (row.rsize < 2 || (row.render[row.rsize - 2] != '*' ||
            row.render[row.rsize - 1] != '/')))
        return 1;
    return 0;
}

/* Set every byte of row.hl (that corresponds to every character in the line)
 * to the right syntax highlight type (HL_* defines). */
void editorUpdateSyntax(erow* row)
{
    row.hl = cast(ubyte*) realloc(row.hl, row.rsize);
    memset(row.hl, HL_NORMAL, row.rsize);

    if (ED.syntax == null)
        return; /* No syntax, everything is HL_NORMAL. */

    int i, prev_sep, in_string, in_comment;
    char* p;
    char** keywords = ED.syntax.keywords;
    char* scs = ED.syntax.singleline_comment_start.ptr;
    char* mcs = ED.syntax.multiline_comment_start.ptr;
    char* mce = ED.syntax.multiline_comment_end.ptr;

    /* Point to the first non-space char. */
    p = row.render;
    i = 0; /* Current char offset */
    while (*p && isspace(*p))
    {
        p++;
        i++;
    }
    prev_sep = 1; /* Tell the parser if 'i' points to start of word. */
    in_string = 0; /* Are we inside "" or '' ? */
    in_comment = 0; /* Are we inside multi-line comment? */

    /* If the previous line has an open comment, this line starts
     * with an open comment state. */
    if (row.idx > 0 && editorRowHasOpenComment(&ED.row[row.idx - 1]))
        in_comment = 1;

    while (*p)
    {
        /* Handle // comments. */
        if (prev_sep && *p == scs[0] && *(p + 1) == scs[1])
        {
            /* From here to end is a comment */
            memset(row.hl + i, HL_COMMENT, row.size - i);
            return;
        }

        /* Handle multi line comments. */
        if (in_comment)
        {
            row.hl[i] = HL_MLCOMMENT;
            if (*p == mce[0] && *(p + 1) == mce[1])
            {
                row.hl[i + 1] = HL_MLCOMMENT;
                p += 2;
                i += 2;
                in_comment = 0;
                prev_sep = 1;
                continue;
            }
            else
            {
                prev_sep = 0;
                p++;
                i++;
                continue;
            }
        }
        else if (*p == mcs[0] && *(p + 1) == mcs[1])
        {
            row.hl[i] = HL_MLCOMMENT;
            row.hl[i + 1] = HL_MLCOMMENT;
            p += 2;
            i += 2;
            in_comment = 1;
            prev_sep = 0;
            continue;
        }

        /* Handle "" and '' */
        if (in_string)
        {
            row.hl[i] = HL_STRING;
            if (*p == '\\')
            {
                row.hl[i + 1] = HL_STRING;
                p += 2;
                i += 2;
                prev_sep = 0;
                continue;
            }
            if (*p == in_string)
                in_string = 0;
            p++;
            i++;
            continue;
        }
        else
        {
            if (*p == '"' || *p == '\'')
            {
                in_string = *p;
                row.hl[i] = HL_STRING;
                p++;
                i++;
                prev_sep = 0;
                continue;
            }
        }

        /* Handle non printable chars. */
        if (!isprint(*p))
        {
            row.hl[i] = HL_NONPRINT;
            p++;
            i++;
            prev_sep = 0;
            continue;
        }

        /* Handle numbers */
        if ((isdigit(*p) && (prev_sep || row.hl[i - 1] == HL_NUMBER)) ||
            (*p == '.' && i > 0 && row.hl[i - 1] == HL_NUMBER))
        {
            row.hl[i] = HL_NUMBER;
            p++;
            i++;
            prev_sep = 0;
            continue;
        }

        /* Handle keywords and lib calls */
        if (prev_sep)
        {
            int j;
            for (j = 0; keywords[j]; j++)
            {
                size_t klen = strlen(keywords[j]);
                int kw2 = keywords[j][klen - 1] == '|';
                if (kw2)
                    klen--;

                if (!memcmp(p, keywords[j], klen) &&
                    is_separator(*(p + klen)))
                {
                    /* Keyword */
                    memset(row.hl + i, kw2 ? HL_KEYWORD2 : HL_KEYWORD1, klen);
                    p += klen;
                    i += klen;
                    break;
                }
            }
            if (keywords[j] != NULL)
            {
                prev_sep = 0;
                continue; /* We had a keyword match */
            }
        }

        /* Not special chars */
        prev_sep = is_separator(*p);
        p++;
        i++;
    }

    /* Propagate syntax change to the next row if the open commen
     * state changed. This may recursively affect all the following rows
     * in the file. */
    int oc = editorRowHasOpenComment(row);
    if (row.hl_oc != oc && row.idx + 1 < ED.numrows)
        editorUpdateSyntax(&ED.row[row.idx + 1]);
    row.hl_oc = oc;
}

/* Maps syntax highlight token types to terminal colors. */
int editorSyntaxToColor(int hl)
{
    switch (hl)
    {
    case HL_COMMENT, HL_MLCOMMENT:
        return 36; /* cyan */
    case HL_KEYWORD1:
        return 33; /* yellow */
    case HL_KEYWORD2:
        return 32; /* green */
    case HL_STRING:
        return 35; /* magenta */
    case HL_NUMBER:
        return 31; /* red */
    case HL_MATCH:
        return 34; /* blu */
    default:
        return 37; /* white */
    }
}

/* ======================= Editor rows implementation ======================= */

/* Update the rendered version and the syntax highlight of a row. */
void editorUpdateRow(erow* row)
{
    uint tabs = 0, nonprint = 0;
    int j, idx;

    /* Create a version of the row we can directly print on the screen,
     * respecting tabs, substituting non printable characters with '?'. */
    free(row.render);
    for (j = 0; j < row.size; j++)
        if (row.chars[j] == TAB)
            tabs++;

    ulong allocsize =
        cast(ulong) row.size + tabs * 8 + nonprint * 9 + 1;
    if (allocsize > uint.max)
    {
        writeln("Some line of the edited file is too long for kilo");
        exit(1);
    }

    row.render = cast(char*) malloc(row.size + tabs * 8 + nonprint * 9 + 1);
    idx = 0;
    for (j = 0; j < row.size; j++)
    {
        if (row.chars[j] == TAB)
        {
            row.render[idx++] = ' ';
            while ((idx + 1) % 8 != 0)
                row.render[idx++] = ' ';
        }
        else
        {
            row.render[idx++] = row.chars[j];
        }
    }
    row.rsize = idx;
    row.render[idx] = '\0';

    /* Update the syntax highlighting attributes of the row. */
    editorUpdateSyntax(row);
}

/* Insert a row at the specified position, shifting the other rows on the bottom
 * if required. */
void editorInsertRow(int at, char* s, size_t len)
{
    if (at > ED.numrows)
        return;
    ED.row = cast(erow*) realloc(ED.row, erow.sizeof * (ED.numrows + 1));
    if (at != ED.numrows)
    {
        memmove(ED.row + at + 1, ED.row + at, ED.row[0].sizeof * (ED.numrows - at));
        for (int j = at + 1; j <= ED.numrows; j++)
            ED.row[j].idx++;
    }
    ED.row[at].size = cast(int) len;
    ED.row[at].chars = cast(char*) malloc(len + 1);
    memcpy(ED.row[at].chars, s, len + 1);
    ED.row[at].hl = null;
    ED.row[at].hl_oc = 0;
    ED.row[at].render = null;
    ED.row[at].rsize = 0;
    ED.row[at].idx = at;
    editorUpdateRow(ED.row + at);
    ED.numrows++;
    ED.dirty++;
}

/* Free row's heap allocated stuff. */
void editorFreeRow(erow* row)
{
    free(row.render);
    free(row.chars);
    free(row.hl);
}

/* Remove the row at the specified position, shifting the remainign on the
 * top. */
void editorDelRow(int at)
{
    erow* row;

    if (at >= ED.numrows)
        return;
    row = ED.row + at;
    editorFreeRow(row);
    memmove(ED.row + at, ED.row + at + 1, ED.row[0].sizeof * (ED.numrows - at - 1));
    for (int j = at; j < ED.numrows - 1; j++)
        ED.row[j].idx++;

    ED.numrows--;
    ED.dirty++;
}

/* Turn the editor rows into a single heap-allocated string.
 * Returns the pointer to the heap-allocated string and populate the
 * integer pointed by 'buflen' with the size of the string, escluding
 * the final nulterm. */
char* editorRowsToString(int* buflen)
{
    char* buf = null;
    char* p;
    int totlen = 0;

    /* Compute count of bytes */
    foreach (j; 0 .. ED.numrows)
        totlen += ED.row[j].size + 1; /* +1 is for "\n" at end of every row */

    *buflen = totlen;
    totlen++; /* Also make space for nulterm */

    p = buf = cast(char*) malloc(totlen);
    foreach (j; 0 .. ED.numrows)
    {
        memcpy(p, ED.row[j].chars, ED.row[j].size);
        p += ED.row[j].size;
        *p = '\n';
        p++;
    }
    *p = '\0';
    return buf;
}

/* Insert a character at the specified position in a row, moving the remaining
 * chars on the right if needed. */
void editorRowInsertChar(erow* row, int at, int c)
{
    if (at > row.size)
    {
        /* Pad the string with spaces if the insert location is outside the
         * current length by more than a single character. */
        int padlen = at - row.size;
        /* In the next line +2 means: new char and null term. */
        row.chars = cast(char*) realloc(row.chars, row.size + padlen + 2);
        memset(row.chars + row.size, ' ', padlen);
        row.chars[row.size + padlen + 1] = '\0';
        row.size += padlen + 1;
    }
    else
    {
        /* If we are in the middle of the string just make space for 1 new
         * char plus the (already existing) null term. */
        row.chars = cast(char*) realloc(row.chars, row.size + 2);
        memmove(row.chars + at + 1, row.chars + at, row.size - at + 1);
        row.size++;
    }
    row.chars[at] = cast(char) c;
    editorUpdateRow(row);
    ED.dirty++;
}

/* Append the string 's' at the end of a row */
void editorRowAppendString(erow* row, char* s, size_t len)
{
    row.chars = cast(char*) realloc(row.chars, row.size + len + 1);
    memcpy(row.chars + row.size, s, len);
    row.size += len;
    row.chars[row.size] = '\0';
    editorUpdateRow(row);
    ED.dirty++;
}

/* Delete the character at offset 'at' from the specified row. */
void editorRowDelChar(erow* row, int at)
{
    if (row.size <= at)
        return;
    memmove(row.chars + at, row.chars + at + 1, row.size - at);
    editorUpdateRow(row);
    row.size--;
    ED.dirty++;
}

/* Insert the specified char at the current prompt position. */
void editorInsertChar(int c)
{
    int filerow = ED.rowoff + ED.cy;
    int filecol = ED.coloff + ED.cx;
    erow* row = (filerow >= ED.numrows) ? null : &ED.row[filerow];

    /* If the row where the cursor is currently located does not exist in our
     * logical representaion of the file, add enough empty rows as needed. */
    if (!row)
    {
        while (ED.numrows <= filerow)
            editorInsertRow(ED.numrows, "".dup.ptr, 0);
    }
    row = &ED.row[filerow];
    editorRowInsertChar(row, filecol, c);
    if (ED.cx == ED.screencols - 1)
        ED.coloff++;
    else
        ED.cx++;
    ED.dirty++;
}

/* Inserting a newline is slightly complex as we have to handle inserting a
 * newline in the middle of a line, splitting the line as needed. */
void editorInsertNewline()
{
    int filerow = ED.rowoff + ED.cy;
    int filecol = ED.coloff + ED.cx;
    erow* row = (filerow >= ED.numrows) ? null : &ED.row[filerow];

    // the "".dup.ptr is to convert string to char*
    if (!row)
    {
        if (filerow == ED.numrows)
        {
            editorInsertRow(filerow, "".dup.ptr, 0);
        }
        else
        {
            return;
        }
    }
    else
    {
        /* If the cursor is over the current line size, we want to conceptually
         * think it's just over the last character. */
        if (filecol >= row.size)
            filecol = row.size;
        if (filecol == 0)
        {
            editorInsertRow(filerow, "".dup.ptr, 0);
        }
        else
        {
            /* We are in the middle of a line. Split it between two rows. */
            editorInsertRow(filerow + 1, row.chars + filecol, row.size - filecol);
            row = &ED.row[filerow];
            row.chars[filecol] = '\0';
            row.size = filecol;
            editorUpdateRow(row);
        }
    }
    if (ED.cy == ED.screenrows - 1)
    {
        ED.rowoff++;
    }
    else
    {
        ED.cy++;
    }
    ED.cx = 0;
    ED.coloff = 0;
}

/* Delete the char at the current prompt position. */
void editorDelChar()
{
    int filerow = ED.rowoff + ED.cy;
    int filecol = ED.coloff + ED.cx;
    erow* row = (filerow >= ED.numrows) ? null : &ED.row[filerow];

    if (!row || (filecol == 0 && filerow == 0))
        return;
    if (filecol == 0)
    {
        /* Handle the case of column 0, we need to move the current line
         * on the right of the previous one. */
        filecol = ED.row[filerow - 1].size;
        editorRowAppendString(&ED.row[filerow - 1], row.chars, row.size);
        editorDelRow(filerow);
        row = null;
        if (ED.cy == 0)
            ED.rowoff--;
        else
            ED.cy--;
        ED.cx = filecol;
        if (ED.cx >= ED.screencols)
        {
            int shift = (ED.screencols - ED.cx) + 1;
            ED.cx -= shift;
            ED.coloff += shift;
        }
    }
    else
    {
        editorRowDelChar(row, filecol - 1);
        if (ED.cx == 0 && ED.coloff)
            ED.coloff--;
        else
            ED.cx--;
    }
    if (row)
        editorUpdateRow(row);
    ED.dirty++;
}

/* Save the current file on disk. Return 0 on success, 1 on error. */
int editorSave()
{
    int len;
    char* buf = editorRowsToString(&len);
    int result = 1;
    // replace the goto
    scope (exit)
    {
        free(buf);
        if (result == 1)
            editorSetStatusMessage("Can't save! I/O error: %s", strerror(errno));
    }

    int fd = open(ED.filename, O_RDWR | O_CREAT, octal!644);
    if (fd == -1)
        return 1;

    scope (exit)
        close(fd);
    /* Use truncate + a single write(2) call in order to make saving
     * a bit safer, under the limits of what we can do in a small editor. */
    if (ftruncate(fd, len) == -1)
        return 1;
    if (cbuiltin.write(fd, buf, len) != len)
        return 1;
    // no errors
    result = 0;

    ED.dirty = 0;
    editorSetStatusMessage("%s bytes written on disk", len);
    return 0;
}

/* ============================= Terminal update ============================ */

/* heap allocated string. This is useful in order to
 * write all the escape sequences in a buffer and flush them to the standard
 * output in a single call, to avoid flickering effects. */
struct abuf
{
    char* b;
    int len;
};

void abAppend(abuf* ab, const char* s, int len)
{
    char* _new = cast(char*) realloc(ab.b, ab.len + len);

    if (_new == null)
        return;
    memcpy(_new + ab.len, s, len);
    ab.b = _new;
    ab.len += len;
}

void abFree(abuf* ab)
{
    free(ab.b);
}

/* ========================= Editor events handling  ======================== */

/* Handle cursor position change because arrow keys were pressed. */
void editorMoveCursor(int key)
{
    int filerow = ED.rowoff + ED.cy;
    int filecol = ED.coloff + ED.cx;
    int rowlen;
    erow* row = (filerow >= ED.numrows) ? null : &ED.row[filerow];

    final switch (key)
    {
    case ARROW_LEFT:
        if (ED.cx == 0)
        {
            if (ED.coloff)
            {
                ED.coloff--;
            }
            else
            {
                if (filerow > 0)
                {
                    ED.cy--;
                    ED.cx = ED.row[filerow - 1].size;
                    if (ED.cx > ED.screencols - 1)
                    {
                        ED.coloff = ED.cx - ED.screencols + 1;
                        ED.cx = ED.screencols - 1;
                    }
                }
            }
        }
        else
        {
            ED.cx -= 1;
        }
        break;
    case ARROW_RIGHT:
        if (row && filecol < row.size)
        {
            if (ED.cx == ED.screencols - 1)
            {
                ED.coloff++;
            }
            else
            {
                ED.cx += 1;
            }
        }
        else if (row && filecol == row.size)
        {
            ED.cx = 0;
            ED.coloff = 0;
            if (ED.cy == ED.screenrows - 1)
            {
                ED.rowoff++;
            }
            else
            {
                ED.cy += 1;
            }
        }
        break;
    case ARROW_UP:
        if (ED.cy == 0)
        {
            if (ED.rowoff)
                ED.rowoff--;
        }
        else
        {
            ED.cy -= 1;
        }
        break;
    case ARROW_DOWN:
        if (filerow < ED.numrows)
        {
            if (ED.cy == ED.screenrows - 1)
            {
                ED.rowoff++;
            }
            else
            {
                ED.cy += 1;
            }
        }
        break;
    }
    /* Fix cx if the current line has not enough chars. */
    filerow = ED.rowoff + ED.cy;
    filecol = ED.coloff + ED.cx;
    row = (filerow >= ED.numrows) ? null : &ED.row[filerow];
    rowlen = row ? row.size : 0;
    if (filecol > rowlen)
    {
        ED.cx -= filecol - rowlen;
        if (ED.cx < 0)
        {
            ED.coloff += ED.cx;
            ED.cx = 0;
        }
    }
}

/* =============================== Find mode ================================ */

enum KILO_QUERY_LEN = 256;
void editorFind(int fd)
{
    char[KILO_QUERY_LEN + 1] query = 0;
    int qlen = 0;
    int last_match = -1; /* Last line where a match was found. -1 for none. */
    int find_next = 0; /* if 1 search next, if -1 search prev. */
    int saved_hl_line = -1; /* No saved HL */
    char* saved_hl = null;

    void FIND_RESTORE_HL()
    {
        if (saved_hl)
        {
            memcpy(ED.row[saved_hl_line].hl, saved_hl, ED.row[saved_hl_line].rsize);
            free(saved_hl);
            saved_hl = null;
        }
    }

    /* Save the cursor position in order to restore it later. */
    int saved_cx = ED.cx, saved_cy = ED.cy;
    int saved_coloff = ED.coloff, saved_rowoff = ED.rowoff;

    while (true)
    {
        editorSetStatusMessage(
            "Search: %s (Use ESC/Arrows/Enter)", query);
        editorRefreshScreen();

        int c = editorReadKey(fd);
        if (c == DEL_KEY || c == CTRL_H || c == BACKSPACE)
        {
            if (qlen != 0)
                query[--qlen] = '\0';
            last_match = -1;
        }
        else if (c == ESC || c == ENTER)
        {
            if (c == ESC)
            {
                ED.cx = saved_cx;
                ED.cy = saved_cy;
                ED.coloff = saved_coloff;
                ED.rowoff = saved_rowoff;
            }
            FIND_RESTORE_HL();
            editorSetStatusMessage("");
            return;
        }
        else if (c == ARROW_RIGHT || c == ARROW_DOWN)
        {
            find_next = 1;
        }
        else if (c == ARROW_LEFT || c == ARROW_UP)
        {
            find_next = -1;
        }
        else if (isprint(c))
        {
            if (qlen < KILO_QUERY_LEN)
            {
                query[qlen++] = cast(char) c;
                query[qlen] = '\0';
                last_match = -1;
            }
        }

        /* Search occurrence. */
        if (last_match == -1)
            find_next = 1;
        if (find_next)
        {
            char* match = null;
            long match_offset = 0;
            int i;
            int current = last_match;

            for (i = 0; i < ED.numrows; i++)
            {
                current += find_next;
                if (current == -1)
                    current = ED.numrows - 1;
                else if (current == ED.numrows)
                    current = 0;
                match = strstr(ED.row[current].render, query.ptr);
                if (match)
                {
                    match_offset = match - ED.row[current].render;
                    break;
                }
            }
            find_next = 0;

            /* Highlight */
            FIND_RESTORE_HL();

            if (match)
            {
                erow* row = &ED.row[current];
                last_match = current;
                if (row.hl)
                {
                    saved_hl_line = current;
                    saved_hl = cast(char*) malloc(row.rsize);
                    memcpy(saved_hl, row.hl, row.rsize);
                    memset(row.hl + match_offset, HL_MATCH, qlen);
                }
                ED.cy = 0;
                ED.cx = cast(int) match_offset;
                ED.rowoff = current;
                ED.coloff = 0;
                /* Scroll horizontally as needed. */
                if (ED.cx > ED.screencols)
                {
                    int diff = ED.cx - ED.screencols;
                    ED.cx -= diff;
                    ED.coloff += diff;
                }
            }
        }
    }
}

/* Try to get the number of columns in the current terminal. If the ioctl()
 * call fails the function will try to query the terminal itself.
 * Returns 0 on success, -1 on error. */
int getWindowSize(int ifd, int ofd, int* rows, int* cols)
{
    winsize ws = void;

    if (ioctl(1, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0)
    {
        /* ioctl() failed. Try to query the terminal itself. */
        int orig_row, orig_col, retval;

        /* Get the initial position so we can restore it later. */
        retval = getCursorPosition(ifd, ofd, &orig_row, &orig_col);
        if (retval == -1)
            return 1;

        /* Go to right/bottom margin and get position. */
        if (kilo.write(ofd, "\x1b[999C\x1b[999B".ptr, 12) != 12)
            return -1;
        retval = getCursorPosition(ifd, ofd, rows, cols);
        if (retval == -1)
            return -1;

        /* Restore position. */
        char[32] seq = void;
        snprintf(seq.ptr, 32, "\x1b[%d;%dH", orig_row, orig_col);
        if (kilo.write(ofd, seq.ptr, strlen(seq.ptr)) == -1)
        {
            /* Can't recover... */
        }
        return 0;
    }
    *cols = ws.ws_col;
    *rows = ws.ws_row;
    return 0;
}

int editorFileWasModified()
{
    return ED.dirty;
}

void updateWindowSize()
{
    if (getWindowSize(STDIN_FILENO, STDOUT_FILENO,
            &ED.screenrows, &ED.screencols) == -1)
    {
        perror("Unable to query the screen for size (columns / rows)");
        exit(1);
    }
    ED.screenrows -= 2; /* Get room for status bar. */
}
// extern(C) because it is called by signal in <signal.h>
extern (C)
void handleSigWinCh(int unused) 
{

    updateWindowSize();
    if (ED.cy > ED.screenrows)
        ED.cy = ED.screenrows - 1;
    if (ED.cx > ED.screencols)
        ED.cx = ED.screencols - 1;
    editorRefreshScreen();
}

void initEditor()
{
    ED.cx = 0;
    ED.cy = 0;
    ED.rowoff = 0;
    ED.coloff = 0;
    ED.numrows = 0;
    ED.row = null;
    ED.dirty = 0;
    ED.filename = null;
    ED.syntax = null;
    updateWindowSize();
    // weird hack to add nothrow and @nogc to the function.
    // doing otherwise would be a lot of work. TODO:
    alias SIGFN = extern(C) void function(int) nothrow @nogc; 
    signal(SIGWINCH, cast(SIGFN)&handleSigWinCh);
}

int main(string[] args)
{
    initGlobals();
    if (args.length != 2)
    {
        writeln(dstderr, "Usage: dilo <filename>");
        // exit is imported from kilo, wich imports stdlib.h
        exit(1);
    }

    initEditor();
    editorSelectSyntaxHighlight(args[1]);
    if (editorOpen(args[1]) == 1)
    {
        writeln(dstderr, "file dont exist");
        exit(1);
    }
    enableRawMode(STDIN_FILENO);
    string msg = "HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find";
    editorSetStatusMessage(msg);

    while (true)
    {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }
}
