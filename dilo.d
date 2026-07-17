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
*/
void editorSetStatusMessage(Ts...)(const char[] fmt, Ts values)
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

/* Remove the row at the specified position, shifting the remainign on the
 * top. */
void editorDelRow(int at)
{
    erow* row;

    if (at >= kilo.E.numrows)
        return;
    row = kilo.E.row + at;
    editorFreeRow(row);
    memmove(kilo.E.row + at, kilo.E.row + at + 1, kilo.E.row[0].sizeof * (kilo.E.numrows - at - 1));
    for (int j = at; j < kilo.E.numrows - 1; j++)
        kilo.E.row[j].idx++;
        
    kilo.E.numrows--;
    kilo.E.dirty++;
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
    foreach (j; 0 .. kilo.E.numrows)
        totlen += kilo.E.row[j].size + 1; /* +1 is for "\n" at end of every row */

    *buflen = totlen;
    totlen++; /* Also make space for nulterm */

    p = buf = cast(char*) malloc(totlen);
    foreach (j; 0 .. kilo.E.numrows)
    {
        memcpy(p, kilo.E.row[j].chars, kilo.E.row[j].size);
        p += kilo.E.row[j].size;
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
    kilo.E.dirty++;
}

/* Append the string 's' at the end of a row */
void editorRowAppendString(erow* row, char* s, size_t len)
{
    row.chars = cast(char*) realloc(row.chars, row.size + len + 1);
    memcpy(row.chars + row.size, s, len);
    row.size += len;
    row.chars[row.size] = '\0';
    editorUpdateRow(row);
    kilo.E.dirty++;
}

/* Delete the character at offset 'at' from the specified row. */
void editorRowDelChar(erow* row, int at)
{
    if (row.size <= at)
        return;
    memmove(row.chars + at, row.chars + at + 1, row.size - at);
    editorUpdateRow(row);
    row.size--;
    kilo.E.dirty++;
}

/* Insert the specified char at the current prompt position. */
void editorInsertChar(int c)
{
    int filerow = kilo.E.rowoff + kilo.E.cy;
    int filecol = kilo.E.coloff + kilo.E.cx;
    erow* row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];

    /* If the row where the cursor is currently located does not exist in our
     * logical representaion of the file, add enough empty rows as needed. */
    if (!row)
    {
        while (kilo.E.numrows <= filerow)
            editorInsertRow(kilo.E.numrows, "".dup.ptr, 0);
    }
    row = &kilo.E.row[filerow];
    editorRowInsertChar(row, filecol, c);
    if (kilo.E.cx == kilo.E.screencols - 1)
        kilo.E.coloff++;
    else
        kilo.E.cx++;
    kilo.E.dirty++;
}

/* Inserting a newline is slightly complex as we have to handle inserting a
 * newline in the middle of a line, splitting the line as needed. */
void editorInsertNewline()
{
    int filerow = kilo.E.rowoff + kilo.E.cy;
    int filecol = kilo.E.coloff + kilo.E.cx;
    erow* row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];

    // the "".dup.ptr is to convert string to char*
    if (!row)
    {
        if (filerow == kilo.E.numrows)
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
            row = &kilo.E.row[filerow];
            row.chars[filecol] = '\0';
            row.size = filecol;
            editorUpdateRow(row);
        }
    }
    if (kilo.E.cy == kilo.E.screenrows - 1)
    {
        kilo.E.rowoff++;
    }
    else
    {
        kilo.E.cy++;
    }
    kilo.E.cx = 0;
    kilo.E.coloff = 0;
}

/* Delete the char at the current prompt position. */
void editorDelChar()
{
    int filerow = kilo.E.rowoff + kilo.E.cy;
    int filecol = kilo.E.coloff + kilo.E.cx;
    erow* row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];

    if (!row || (filecol == 0 && filerow == 0))
        return;
    if (filecol == 0)
    {
        /* Handle the case of column 0, we need to move the current line
         * on the right of the previous one. */
        filecol = kilo.E.row[filerow - 1].size;
        editorRowAppendString(&kilo.E.row[filerow - 1], row.chars, row.size);
        editorDelRow(filerow);
        row = null;
        if (kilo.E.cy == 0)
            kilo.E.rowoff--;
        else
            kilo.E.cy--;
        kilo.E.cx = filecol;
        if (kilo.E.cx >= kilo.E.screencols)
        {
            int shift = (kilo.E.screencols - kilo.E.cx) + 1;
            kilo.E.cx -= shift;
            kilo.E.coloff += shift;
        }
    }
    else
    {
        editorRowDelChar(row, filecol - 1);
        if (kilo.E.cx == 0 && kilo.E.coloff)
            kilo.E.coloff--;
        else
            kilo.E.cx--;
    }
    if (row)
        editorUpdateRow(row);
    kilo.E.dirty++;
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

    int fd = open(kilo.E.filename, O_RDWR | O_CREAT, octal!644);
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

    kilo.E.dirty = 0;
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

    if (_new == NULL)
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
    int filerow = kilo.E.rowoff + kilo.E.cy;
    int filecol = kilo.E.coloff + kilo.E.cx;
    int rowlen;
    erow* row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];

    final switch (key)
    {
    case ARROW_LEFT:
        if (kilo.E.cx == 0)
        {
            if (kilo.E.coloff)
            {
                kilo.E.coloff--;
            }
            else
            {
                if (filerow > 0)
                {
                    kilo.E.cy--;
                    kilo.E.cx = kilo.E.row[filerow - 1].size;
                    if (kilo.E.cx > kilo.E.screencols - 1)
                    {
                        kilo.E.coloff = kilo.E.cx - kilo.E.screencols + 1;
                        kilo.E.cx = kilo.E.screencols - 1;
                    }
                }
            }
        }
        else
        {
            kilo.E.cx -= 1;
        }
        break;
    case ARROW_RIGHT:
        if (row && filecol < row.size)
        {
            if (kilo.E.cx == kilo.E.screencols - 1)
            {
                kilo.E.coloff++;
            }
            else
            {
                kilo.E.cx += 1;
            }
        }
        else if (row && filecol == row.size)
        {
            kilo.E.cx = 0;
            kilo.E.coloff = 0;
            if (kilo.E.cy == kilo.E.screenrows - 1)
            {
                kilo.E.rowoff++;
            }
            else
            {
                kilo.E.cy += 1;
            }
        }
        break;
    case ARROW_UP:
        if (kilo.E.cy == 0)
        {
            if (kilo.E.rowoff)
                kilo.E.rowoff--;
        }
        else
        {
            kilo.E.cy -= 1;
        }
        break;
    case ARROW_DOWN:
        if (filerow < kilo.E.numrows)
        {
            if (kilo.E.cy == kilo.E.screenrows - 1)
            {
                kilo.E.rowoff++;
            }
            else
            {
                kilo.E.cy += 1;
            }
        }
        break;
    }
    /* Fix cx if the current line has not enough chars. */
    filerow = kilo.E.rowoff + kilo.E.cy;
    filecol = kilo.E.coloff + kilo.E.cx;
    row = (filerow >= kilo.E.numrows) ? null : &kilo.E.row[filerow];
    rowlen = row ? row.size : 0;
    if (filecol > rowlen)
    {
        kilo.E.cx -= filecol - rowlen;
        if (kilo.E.cx < 0)
        {
            kilo.E.coloff += kilo.E.cx;
            kilo.E.cx = 0;
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
            memcpy(kilo.E.row[saved_hl_line].hl, saved_hl, kilo.E.row[saved_hl_line].rsize);
            free(saved_hl);
            saved_hl = null;
        }
    }

    /* Save the cursor position in order to restore it later. */
    int saved_cx = kilo.E.cx, saved_cy = kilo.E.cy;
    int saved_coloff = kilo.E.coloff, saved_rowoff = kilo.E.rowoff;

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
                kilo.E.cx = saved_cx;
                kilo.E.cy = saved_cy;
                kilo.E.coloff = saved_coloff;
                kilo.E.rowoff = saved_rowoff;
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

            for (i = 0; i < kilo.E.numrows; i++)
            {
                current += find_next;
                if (current == -1)
                    current = kilo.E.numrows - 1;
                else if (current == kilo.E.numrows)
                    current = 0;
                match = strstr(kilo.E.row[current].render, query.ptr);
                if (match)
                {
                    match_offset = match - kilo.E.row[current].render;
                    break;
                }
            }
            find_next = 0;

            /* Highlight */
            FIND_RESTORE_HL();

            if (match)
            {
                erow* row = &kilo.E.row[current];
                last_match = current;
                if (row.hl)
                {
                    saved_hl_line = current;
                    saved_hl = cast(char*) malloc(row.rsize);
                    memcpy(saved_hl, row.hl, row.rsize);
                    memset(row.hl + match_offset, HL_MATCH, qlen);
                }
                kilo.E.cy = 0;
                kilo.E.cx = cast(int) match_offset;
                kilo.E.rowoff = current;
                kilo.E.coloff = 0;
                /* Scroll horizontally as needed. */
                if (kilo.E.cx > kilo.E.screencols)
                {
                    int diff = kilo.E.cx - kilo.E.screencols;
                    kilo.E.cx -= diff;
                    kilo.E.coloff += diff;
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
        cio.snprintf(seq.ptr, 32, "\x1b[%d;%dH", orig_row, orig_col);
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
// extern(C) because it is called by signal in <signal.h>
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
    editorSetStatusMessage(msg);

    while (true)
    {
        editorRefreshScreen();
        editorProcessKeypress(STDIN_FILENO);
    }
}
