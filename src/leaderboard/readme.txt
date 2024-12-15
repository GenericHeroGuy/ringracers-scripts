LeaderboardX: A continuation of Not's Leaderboard
Brought to you by GenericHeroGuy and months of suffering
Based on the Sunflower's Garden version

New features in LeaderboardX:
	* A compact binary store format
	* Ghosts, remade from scratch
	* Ring Racers support
	* Battle mode support: break the targets!
	* Combi Ring support (Kart only)
	* Appearance support
	* Record moving/deleting without updating coldstore
	* Player profiles (RR only)

This readme is only for LeaderboardX changes.
For more info, see the original's MB page:
https://mb.srb2.org/addons/time-attack-leaderboard.3742/

Also thanks to Indev and Alug :Blobcatpats:


Setup
========================================
To use LeaderboardX, you must set lb_directory to e.g. your server's name.
Remember to put this in your config!
After that, it should Just Work(tm)


Converting text format to binary
========================================
	1. Start with old Leaderboard
	2. Write a new coldstore, by using `lb_move_records`
	3. Switch to LeaderboardX
	4. Run `lb_convert_to_binary`
This converts luafiles/leaderboard.coldstore.txt to binary format,
and writes it to the current directory set in lb_directory.


Cold stores
========================================
If you have many records on your server, you'll eventually suffer from
severe join lag, due to the large amount of data sent through NetVars.

To fix this, use cold stores to save record data in a Lua script.
This script can then be loaded by clients to update the records in their store,
instead of having to download them from the server and causing lag.

Use `lb_write_coldstore <filename>` to write a new coldstore.
Once done, <filename>_0.txt will be written to your luafiles folder.
This file is segmented to get around the 1-megabyte limit; if you end up
with multiple segments (like <filename>_1.txt), concatenate them with
`copy /b <filename>_0.txt + <filename>_1.txt out.txt`.

Finally, take the output file, rename .txt to .lua, and add it to your server.
Don't forget the file or else records will go missing for clients!


Ghosts
========================================
Ghosts are recorded and saved whenever you set a new record.
You can watch ghosts by pressing Custom 2 (Lua B).

Use D-pad to rotate the camera, or press Custom 2 again to switch ghosts.
Press Custom 1 (Lua A) to toggle playback controls. Use D-pad to navigate.


Commands
========================================
lb_statistics:
	Random bits of information about your leaderboard data.
	Mostly useful for checking savegame size (size of diff)

lb_encore:
	New name for encore command (kartencore became encore in RR)

lb_write_coldstore:
	Writes a new coldstore script to luafiles/<filename>.txt

lb_convert_to_binary:
	Convert luafiles/leaderboard.coldstore.txt to binary

Cvars
========================================
lb_directory:
	Name of server's store directory

lb_ringboxes: (RR only)
	Set the behavior of item boxes.
	Sneakers:    Only give sneakers (Kart-style)
	Multiplayer: Ring boxes, with default behavior
	TA:          Ring boxes, with bigger payouts

lb_ghost:
	Toggle ghosts server-wide.
	If disabled, ghosts will not be recorded or downloaded
lb_ghost_hide:
	Toggle ghosts locally. Also disables downloads
lb_ghost_maxsize:
	Maximum size of ghosts, in bytes

lb_net_filetransfer: (RR only)
	Enable Lua file transfers for near-instant ghost downloads
lb_net_bandwidth:
	How many bytes of NetXCmd bandwidth to use
lb_net_timeout:
	Tics to wait before timing out connections
lb_net_log:
	Logging level, mostly for debugging.
	Set to "None" to shut up
lb_net_droptest:
	Packet drop testing (why is this still here?)
