# PeerDrop

Send files and folders directly to anyone, anywhere — no accounts, no cloud, no size limits.

PeerDrop is a macOS menu bar app that connects peers directly over the internet using end-to-end encrypted connections. Drop a file onto a contact's panel and they receive it in real time. That's it.

---

## How it works

You have a **Peer ID** — a 64-character string. Share it with someone and they can send you files directly. No signup, no email, no server in the middle.

Connections are peer-to-peer and encrypted. Files go straight from your machine to theirs.

---

## Getting started

### Install

Download the latest release from the [Releases](../../releases) page and move `PeerDrop.app` to your Applications folder.

Launch it — a small icon appears in your menu bar.

### Connect with someone

1. Open PeerDrop and click the copy button next to **My ID**
2. Send that ID to someone (iMessage, email, anything)
3. They paste it into the search bar in their PeerDrop and hit **Connect**
4. Once connected, their name appears under **PEOPLE**

They do the same with your ID so you can send to them too.

### Send a file or folder

Click a person's name to open their send panel. Drag any file or folder onto it. They receive it immediately — no waiting for an upload to finish.

### Add your own devices

Want to send files between your own Macs? Copy `~/.peerdrop/seed` from one Mac to the same path on the other. Both devices will appear under **MY DEVICES** automatically next time they're both online.

> **Keep your seed file safe.** It's your identity. Back it up somewhere secure and don't share it with anyone you don't want acting as you.

---

## Requirements

- macOS 13 or later

---

## Privacy

PeerDrop does not have a server. It does not store your files. It does not know who you are.

Connections are established through [Hyperswarm](https://github.com/holepunchto/hyperswarm)'s distributed hash table and encrypted with the Noise protocol. Your Peer ID is derived from a local seed file that never leaves your machine unless you copy it yourself.

