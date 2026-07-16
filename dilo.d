import kilo;

import std.stdio : writeln;
import std.format : sformat;
import std;

// resolve conflicts between libc and core.stdc.
// we prefer D's version, more type safety.
alias libc = core.stdc;
alias cio = libc.stdio;
/* making clear that kilo namespace is used
 to resolve conflicts between symbols built in C
  and D's reimport of those symbols in core.* */
alias cbuiltin = kilo;

/*Process events arriving from the standard input, which is,
* the user  is typing stuff on the terminal. */
enum KILO_QUIT_TIMES = 3;

/*When the file is modified, requires Ctrl-q to be
* pressed N times before actually quitting. */
int quit_times = KILO_QUIT_TIMES;
void editorProcessKeypress(int fd)
{

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
        if (kilo.E.dirty && quit_times)
        {
            editorSetStatusMessage_D("WARNING!!! File has unsaved changes."
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
        if (c == PAGE_UP && kilo.E.cy != 0)
            kilo.E.cy = 0;
        else if (c == PAGE_DOWN && kilo.E.cy != kilo.E.screenrows - 1)
            kilo.E.cy = kilo.E.screenrows - 1;
        {
            int times = kilo.E.screenrows;
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
    for (y = 0; y < kilo.E.screenrows; y++)
    {
        int filerow = kilo.E.rowoff + y;

        if (filerow >= kilo.E.numrows)
        {
            if (kilo.E.numrows == 0 && y == kilo.E.screenrows / 3)
            {
                char[80] welcome = void;
                int welcomelen = cio.snprintf(welcome.ptr, welcome.length,
                    "Kilo editor -- verison %s\x1b[0K\r\n", KILO_VERSION.ptr);
                int padding = (kilo.E.screencols - welcomelen) / 2;
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

        r = &kilo.E.row[filerow];

        int len = r.rsize - kilo.E.coloff;
        int current_color = -1;
        if (len > 0)
        {
            if (len > kilo.E.screencols)
                len = kilo.E.screencols;
            char* c = r.render + kilo.E.coloff;
            ubyte* hl = r.hl + kilo.E.coloff;
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
                        int clen = cio.snprintf(_buf.ptr, _buf.length, "\x1b[%dm", color);
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
    int len = cio.snprintf(status.ptr, status.length, "%.20s - %d lines %s",
        kilo.E.filename, kilo.E.numrows, kilo.E.dirty ? "(modified)".ptr : "".ptr);
    int rlen = cio.snprintf(rstatus.ptr, rstatus.length,
        "%d/%d", kilo.E.rowoff + kilo.E.cy + 1, kilo.E.numrows);
    if (len > kilo.E.screencols)
        len = kilo.E.screencols;
    abAppend(&ab, status.ptr, len);
    while (len < kilo.E.screencols)
    {
        if (kilo.E.screencols - len == rlen)
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
    size_t msglen = strlen(kilo.E.statusmsg.ptr);
    if (msglen && time(null) - kilo.E.statusmsg_time < 5)
        abAppend(&ab, kilo.E.statusmsg.ptr, msglen <= kilo.E.screencols ? cast(int) msglen
                : kilo.E.screencols);

    /* Put cursor at its current position. Note that the horizontal position
     * at which the cursor is displayed may be different compared to 'E.cx'
     * because of TABs. */
    int j;
    int cx = 1;
    int filerow = kilo.E.rowoff + kilo.E.cy;
    erow* row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];
    if (row)
    {
        for (j = kilo.E.coloff; j < (kilo.E.cx + kilo.E.coloff); j++)
        {
            if (j < row.size && row.chars[j] == TAB)
                cx += 7 - ((cx) % 8);
            cx++;
        }
    }
    cio.snprintf(buf.ptr, buf.length, "\x1b[%d;%dH", kilo.E.cy + 1, cx);
    abAppend(&ab, buf.ptr, cast(int) strlen(buf.ptr));
    abAppend(&ab, "\x1b[?25h", 6); /* Show cursor. */
    cbuiltin.write(STDOUT_FILENO, ab.b, ab.len);
    abFree(&ab);
}
/*Set an editor status message for the second line
  of the status, at the end of the screen.
  
  for now it is only going to be used by main function
  and the C version will be kept until other functions
  are translated
*/
void editorSetStatusMessage_D(Ts...)(const char[] fmt, Ts values)
{
    //char[80] buf = E.statusmsg;
    sformat(kilo.E.statusmsg, fmt, values);
    kilo.E.statusmsg_time = time(null);
}

// dmd is not able to set errno since
// it's a macro, made a wrapper function in C.
import dilo_errno : setErrno;

int enableRawMode(int fd)
{
    /* Raw mode: 1960 magic shit. */
    termios raw;
    if (kilo.E.rawmode)
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

    kilo.E.rawmode = 1;
    // no error, set to false so that scope(exit)
    // dont modify errno
    err = false;
    return 0;
}

/* Load the specified program in the editor memory and returns 0 on success
 * or 1 on error. */
int editorOpen(char* filename)
{
    cio.FILE* fp;

    kilo.E.dirty = 0;
    free(kilo.E.filename);
    size_t fnlen = strlen(filename) + 1;
    kilo.E.filename = cast(char*) malloc(fnlen);
    memcpy(kilo.E.filename, filename, fnlen);

    fp = cio.fopen(filename, "r");
    if (!fp)
    {
        if (errno != ENOENT)
        {
            cio.perror("Opening file");
            exit(1);
        }
        return 1;
    }

    char* line = null;
    size_t linecap = 0;
    cbuiltin.ssize_t linelen;
    // cast away the shared in fp.
    while ((linelen = getline(&line, &linecap, cast(cbuiltin._IO_FILE*) fp)) != -1)
    {
        if (linelen && (line[linelen - 1] == '\n' || line[linelen - 1] == '\r'))
            line[--linelen] = '\0';
        editorInsertRow(kilo.E.numrows, line, linelen);
    }
    free(line);
    fclose(fp);
    kilo.E.dirty = 0;
    return 0;
}

/* Select the syntax highlight scheme depending on the filename,
 * setting it in the global state E.syntax. */
void editorSelectSyntaxHighlight(const char* filename)
{
    foreach (size_t j; 0 .. HLDB_ENTRIES)
    {
        editorSyntax* s = &HLDB[j];
        size_t i = 0;
        while (s.filematch[i])
        {
            char* p;
            size_t patlen = strlen(s.filematch[i]);
            if ((p = strstr(filename, s.filematch[i])) != NULL)
            {
                if (s.filematch[i][0] != '.' || p[patlen] == '\0')
                {
                    kilo.E.syntax = s;
                    return;
                }
            }
            i++;
        }
    }
}

int editorFileWasModified()
{
    return kilo.E.dirty;
}

void updateWindowSize()
{
    if (getWindowSize(STDIN_FILENO, STDOUT_FILENO,
            &kilo.E.screenrows, &kilo.E.screencols) == -1)
    {
        cio.perror("Unable to query the screen for size (columns / rows)");
        exit(1);
    }
    kilo.E.screenrows -= 2; /* Get room for status bar. */
}

extern (C)
void handleSigWinCh(int unused)
{

    updateWindowSize();
    if (kilo.E.cy > kilo.E.screenrows)
        kilo.E.cy = kilo.E.screenrows - 1;
    if (kilo.E.cx > kilo.E.screencols)
        kilo.E.cx = kilo.E.screencols - 1;
    editorRefreshScreen();
}

void initEditor()
{
    kilo.E.cx = 0;
    kilo.E.cy = 0;
    kilo.E.rowoff = 0;
    kilo.E.coloff = 0;
    kilo.E.numrows = 0;
    kilo.E.row = null;
    kilo.E.dirty = 0;
    kilo.E.filename = null;
    kilo.E.syntax = null;
    updateWindowSize();
    signal(SIGWINCH, &handleSigWinCh);
}

int main(string[] args)
{
    if (args.length != 2)
    {
        writeln(std.stdio.stderr, "Usage: dilo <filename>");
        // exit is imported from kilo, wich imports stdlib.h
        exit(1);
    }
    // append null terminator to 2nd arg
    // make it compatible with C code.
    char[] filename = cast(char[])(args[1] ~ '\0');

    initEditor();
    editorSelectSyntaxHighlight(filename.ptr);
    if (editorOpen(filename.ptr) == 1)
    {
        writeln(std.stdio.stderr, "file dont exist");
        exit(1);
    }
    enableRawMode(STDIN_FILENO);
    string msg = "HELP: Ctrl-S = save | Ctrl-Q = quit | Ctrl-F = find";
    editorSetStatusMessage_D(msg);

    while (true)
    {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }
}
