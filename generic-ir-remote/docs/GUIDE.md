# SmartThings Generic IR Remote Guide

This guide explains how to install the SmartThings Edge driver and control air conditioners, TVs, and other infrared devices with a compatible Zigbee IR remote.

## Requirements

- A SmartThings hub
- A TS1201-compatible Zigbee IR remote
  - Confirm that the Tuya or MOES device is a Zigbee model. Wi-Fi models do not work with this driver.
  - A model listing `TS1201` or `TZ3290` is the clearest compatibility indicator.
- The SmartThings app and a Samsung account

## Install the driver and connect the IR remote

1. Open the [SmartThings Generic IR Remote channel](https://callaway.smartthings.com/channels/fd5a6ac8-0c02-4cd0-983e-5e94287e96d2) and sign in with your Samsung account.
2. Enroll your SmartThings hub in the channel.
3. Select **SmartThings Generic IR Remote** under **Available Drivers** to install it on the hub.
4. If the IR remote is not paired yet, use **Add device → Scan nearby** in the SmartThings app and start the remote's pairing procedure.
5. If the remote is already paired with a different driver, open the menu in the upper-right corner of its device page, choose **Driver → Select another driver**, and switch to **SmartThings Generic IR Remote**.

Example of selecting the driver from the SmartThings device page:

![Selecting the driver from the SmartThings device page](assets/1.png)

If the device is not discovered or does not pair, check its exact model and confirm that it is a Zigbee device. TS1201-compatible devices can still behave differently across hardware revisions.

## Create an air conditioner remote

1. On the physical IR remote's device page, open **Remote type** and select **Air conditioner - protocol**.
   - If no protocol works, choose **Air conditioner - learning** or **Air conditioner - protocol with learning** to capture appliance states.
2. Enter a **Remote name**.
3. Tap **Create remote**. A new air conditioner remote appears in your SmartThings device list.
4. Open the new AC device and select the manufacturer and remote model under **AC protocol / model**. Use the model number printed on the original remote when available. The brand alone may not identify the right variant, so check the appliance's response as you try options.
5. Set the mode, target temperature, fan speed, and supported swing directions, then check that the appliance responds.

Protocol mode generates IR signals containing the air conditioner's full state. The choices are software protocol/model variants; an entry in the list does not mean that it has been verified on a specific physical air conditioner.

![Creating an air conditioner remote and selecting its protocol](assets/2.png)

![Air conditioner controls and an example protocol selection](assets/4.png)

### Learn AC states when needed

Use **Learn AC states** if no listed protocol/model works or the appliance does not respond as expected.

1. Enable **Edit capture state without sending**.
2. Set power, mode, target temperature, fan speed, and swing on the SmartThings screen. This edits a draft and does not transmit IR.
3. Set the original remote to the same state, tap **Learn**, and press its button to capture the signal.
4. Use **Test** to transmit the saved state and check the air conditioner.
5. Turn off capture setup mode when you are done.

## Create a TV, fan, or other remote

Use the same remote-creation steps and choose the appropriate **Remote type**:

- **TV**: Maps IR signals to the SmartThings keypad and navigation controls.
- **Fan**: Learns power actions for now.
- **Generic IR switch**: Learns power-on and power-off signals for a switch device.
- **Generic IR button**: Learns one signal and replays it with the **Push** command.

![A TV remote shown in the device list](assets/3.png)

## Learn and test signals

1. Open the new remote and choose the signal to learn.
2. Tap **Learn selected signal**.
3. Point the original remote toward the IR remote and press the button for that action.
4. When the learning status changes to **Saved**, tap **Test saved signal** to check it.

Some TV signals may appear in the learning list even when the corresponding button is not visible on the device page. Look for the action in the signal list.

![TV keypad and signal-learning controls](assets/5.png)

## Troubleshooting and notes

- Infrared cannot pass through walls or obstacles. Keep a clear line of sight between the IR remote and the appliance.
- A completed status means the IR transmission finished; it does not confirm that the appliance responded. Check the appliance itself.
- When reporting a compatibility issue, include the IR remote model and hardware revision, SmartThings hub model, and appliance model.
- See the [GitHub repository](https://github.com/Heartade/smartthings-generic-ir-remote) for source code, known limitations, and issue reporting.
