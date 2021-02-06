
<img src"acb.png"><p>



1.) Installation

    just run:
    sudo ./acb_install.sh

2.) Settings

    All parameters stored in ~/.acb/acb.ini
    You could edit this via any editor of you choice.

3.) Security and initial settings

    To get a quick success even you got no own NAS machine, one author offers
    space for demonstration.
    This is totally safe because no data will leave your machine unencrypted
    if you don't switch this off in the settings!
    It will not be very fast and we don't could ensure to hold the data for long time.


4.) Cronjob

    By default a cronjob will be installed to make a backup once a day.
    Edit this by
        crontab -e
    if you don't want automatically started backups or in other periods.


5.) How to backup/restore?

    Use the "little helper" if you are not familiar to bash/console.
    Otherwise do
        "acb"
    which displays all possible commands.

    For quick start:
        acb -b -> makes backup of current folder with all subfolders in same partition
        acb -r -> restores backup to a new subfolder named "acRestore" of current folder and restores data to it 
                  So this will _not_ overwrite current data!


Contact:
https://keybase.io/reinerrusch

    --
    with ideas from:
    M.Blomberg: graphics, menues, installation process
    R.Rusch: backup logic

