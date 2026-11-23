# Your practice folder

These files are yours to break. Nothing here matters: try the commands from
`mhelp commands` on them, delete them, change them, copy them. When you want a
clean copy back, delete the folder and copy it again from `/etc/skel/practice`
(that template is what new accounts get):

```bash
rm -rf ~/practice
cp -r /etc/skel/practice ~/practice
```

What is here:

| File | Use it to try |
|---|---|
| `notes.txt` | `cat`, `less`, `nano`, `cp`, `mv`, `grep` |
| `todo.txt` | `grep`, `sort`, `wc -l`, `>>` to append |
| `contacts.csv` | `grep` for a person, `cut -d, -f1` for the names |
| `folders/` | `cd`, `ls`, `mkdir`, `rmdir` — two empty folders to move around in |

A good first five minutes:

```bash
cd ~/practice
pwd
ls -l
less notes.txt
grep -i milk todo.txt
cp notes.txt copy-of-notes.txt
mv copy-of-notes.txt folders/
rm folders/copy-of-notes.txt
```

Nothing in the practice folder is used by the system, so an experiment cannot
break your desktop. Keep it that way: do not try `rm -rf` experiments on `~` or
on `/` — read the safety section of `mhelp commands` first.
