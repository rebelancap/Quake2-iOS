//
//  SDL2ViewController+Additions.swift
//  Quake2-iOS
//
//  Created by Tom Kidd on 1/28/19.
//

import UIKit
import QuartzCore  // For CACurrentMediaTime

@_silgen_name("cls")
var cls: client_static_t

@_silgen_name("joystick_yaw")
var joystick_yaw: Float

@_silgen_name("joystick_pitch")
var joystick_pitch: Float

@_silgen_name("joystick_forwardmove")
var joystick_forwardmove: Float

@_silgen_name("joystick_sidemove")
var joystick_sidemove: Float

@_silgen_name("ca_disconnected")
var ca_disconnected: Int32

@_silgen_name("con")
var con: console_t

extension SDL_uikitviewcontroller {
    
    // A method of getting around the fact that Swift extensions cannot have stored properties
    // https://medium.com/@valv0/computed-properties-and-extensions-a-pure-swift-approach-64733768112c
    struct Holder {
        static var _fireButton = UIButton()
        static var _jumpButton = UIButton()
        static var _joystickView = JoyStickView(frame: .zero)
        static var _tildeButton = UIButton()
        static var _expandButton = UIButton()
        static var _escapeButton = UIButton()
        static var _quickSaveButton: UIButton!
        static var _quickLoadButton: UIButton!
        static var _buttonStack = UIStackView(frame: .zero)
        static var _buttonStackExpanded = false
        static var _f1Button = UIButton()
        static var _prevWeaponButton = UIButton()
        static var _nextWeaponButton = UIButton()
        static var _rightJoystickView = JoyStickView(frame: .zero)
        static var _dpadView = UIView()
        static var _dpadUpButton = UIButton()
        static var _dpadDownButton = UIButton()
        static var _dpadLeftButton = UIButton()
        static var _dpadRightButton = UIButton()
        static var _enterButton = UIButton()
        static var _backButton = UIButton()
        static var _quitButton = UIButton()
        static var _lastLookTime: TimeInterval = 0.0
     }

    var fireButton:UIButton {
        get {
            return Holder._fireButton
        }
        set(newValue) {
            Holder._fireButton = newValue
        }
    }
    
    var jumpButton:UIButton {
        get {
            return Holder._jumpButton
        }
        set(newValue) {
            Holder._jumpButton = newValue
        }
    }
    
    var joystickView:JoyStickView {
        get {
            return Holder._joystickView
        }
        set(newValue) {
            Holder._joystickView = newValue
        }
    }
    
    var rightJoystickView:JoyStickView {
        get {
            return Holder._rightJoystickView
        }
        set(newValue) {
            Holder._rightJoystickView = newValue
        }
    }

    var tildeButton:UIButton {
        get {
            return Holder._tildeButton
        }
        set(newValue) {
            Holder._tildeButton = newValue
        }
    }

    var escapeButton:UIButton {
        get {
            return Holder._escapeButton
        }
        set(newValue) {
            Holder._escapeButton = newValue
        }
    }

    var expandButton:UIButton {
        get {
            return Holder._expandButton
        }
        set(newValue) {
            Holder._expandButton = newValue
        }
    }
    
    var quickLoadButton:UIButton {
        get {
            return Holder._quickLoadButton
        }
        set(newValue) {
            Holder._quickLoadButton = newValue
        }
    }
    
    var quickSaveButton:UIButton {
        get {
            return Holder._quickSaveButton
        }
        set(newValue) {
            Holder._quickSaveButton = newValue
        }
    }
    
    var buttonStack:UIStackView {
        get {
            return Holder._buttonStack
        }
        set(newValue) {
            Holder._buttonStack = newValue
        }
    }

    var buttonStackExpanded:Bool {
        get {
            return Holder._buttonStackExpanded
        }
        set(newValue) {
            Holder._buttonStackExpanded = newValue
        }
    }
    
    var f1Button:UIButton {
        get {
            return Holder._f1Button
        }
        set(newValue) {
            Holder._f1Button = newValue
        }
    }
    
    var prevWeaponButton:UIButton {
        get {
            return Holder._prevWeaponButton
        }
        set(newValue) {
            Holder._prevWeaponButton = newValue
        }
    }

    var nextWeaponButton:UIButton {
        get {
            return Holder._nextWeaponButton
        }
        set(newValue) {
            Holder._nextWeaponButton = newValue
        }
    }
    
    var dpadView: UIView {
        get { return Holder._dpadView }
        set { Holder._dpadView = newValue }
    }

    var dpadUpButton: UIButton {
        get { return Holder._dpadUpButton }
        set { Holder._dpadUpButton = newValue }
    }

    var dpadDownButton: UIButton {
        get { return Holder._dpadDownButton }
        set { Holder._dpadDownButton = newValue }
    }

    var dpadLeftButton: UIButton {
        get { return Holder._dpadLeftButton }
        set { Holder._dpadLeftButton = newValue }
    }

    var dpadRightButton: UIButton {
        get { return Holder._dpadRightButton }
        set { Holder._dpadRightButton = newValue }
    }

    var enterButton: UIButton {
        get { return Holder._enterButton }
        set { Holder._enterButton = newValue }
    }

    var backButton: UIButton {
        get { return Holder._backButton }
        set { Holder._backButton = newValue }
    }
    
    var quitButton: UIButton {
        get {
            return Holder._quitButton
        }
        set(newValue) {
            Holder._quitButton = newValue
        }
    }
    
    var lastLookTime: TimeInterval {
        get { return Holder._lastLookTime }
        set { Holder._lastLookTime = newValue }
    }

    @objc func fireButton(rect: CGRect) -> UIButton {
        fireButton = UIButton(frame: CGRect(x: rect.width - 250, y: rect.height - 90, width: 75, height: 75))
        fireButton.setTitle("FIRE", for: .normal)
        fireButton.setBackgroundImage(UIImage(named: "JoyStickBase")!, for: .normal)
        fireButton.addTarget(self, action: #selector(self.firePressed), for: .touchDown)
        fireButton.addTarget(self, action: #selector(self.fireReleased), for: .touchUpInside)
        fireButton.alpha = 0.5
        return fireButton
    }
    
    @objc func jumpButton(rect: CGRect) -> UIButton {
        jumpButton = UIButton(frame: CGRect(x: rect.width - 90, y: rect.height - 135, width: 75, height: 75))
        jumpButton.setTitle("JUMP", for: .normal)
        jumpButton.setBackgroundImage(UIImage(named: "JoyStickBase")!, for: .normal)
        jumpButton.addTarget(self, action: #selector(self.jumpPressed), for: .touchDown)
        jumpButton.addTarget(self, action: #selector(self.jumpReleased), for: .touchUpInside)
        jumpButton.alpha = 0.5
        return jumpButton
    }
    
    @objc func joyStick(rect: CGRect) -> JoyStickView {
        let size = CGSize(width: 100.0, height: 100.0)
        let joystick1Frame = CGRect(origin: CGPoint(x: 50.0,
                                                    y: (rect.height - size.height - 50.0)),
                                    size: size)
        joystickView = JoyStickView(frame: joystick1Frame)
        joystickView.delegate = self
        
        joystickView.movable = false
        joystickView.alpha = 0.5
        joystickView.baseAlpha = 0.5 // let the background bleed thru the base
        joystickView.handleTintColor = UIColor.darkGray // Colorize the handle
        return joystickView
    }
    
    @objc func rightJoyStick(rect: CGRect) -> JoyStickView {
        let size = CGSize(width: 100.0, height: 100.0)
        let rightJoystickFrame = CGRect(origin: CGPoint(x: rect.width - size.width - 50.0,
                                                         y: (rect.height - size.height - 50.0)),
                                        size: size)
        rightJoystickView = JoyStickView(frame: rightJoystickFrame)
        rightJoystickView.delegate = self
        rightJoystickView.tag = 2  // Different tag from left joystick
        
        rightJoystickView.movable = false
        rightJoystickView.alpha = 0.5
        rightJoystickView.baseAlpha = 0.5
        rightJoystickView.handleTintColor = UIColor.darkGray
        return rightJoystickView
    }
    
    @objc func buttonStack(rect: CGRect) -> UIStackView {
        
        
        expandButton = UIButton(type: .custom)
        expandButton.setTitle(" > ", for: .normal)
        expandButton.addTarget(self, action: #selector(self.expand), for: .touchUpInside)
        expandButton.sizeToFit()
        expandButton.alpha = 0.5
        expandButton.frame.size.width = 50

        tildeButton = UIButton(type: .custom)
        tildeButton.setTitle(" ~ ", for: .normal)
        tildeButton.addTarget(self, action: #selector(self.tildePressed), for: .touchDown)
        tildeButton.addTarget(self, action: #selector(self.tildeReleased), for: .touchUpInside)
        tildeButton.alpha = 0
        tildeButton.isHidden = true

        escapeButton = UIButton(type: .custom)
        escapeButton.setTitle(" ESC ", for: .normal)
        escapeButton.addTarget(self, action: #selector(self.escapePressed), for: .touchDown)
        escapeButton.addTarget(self, action: #selector(self.escapeReleased), for: .touchUpInside)
        escapeButton.layer.borderColor = UIColor.white.cgColor
        escapeButton.layer.borderWidth = CGFloat(1)
        escapeButton.alpha = 0
        escapeButton.isHidden = true

        quickSaveButton = UIButton(type: .custom)
        quickSaveButton.setTitle(" QS ", for: .normal)
        quickSaveButton.addTarget(self, action: #selector(self.quickSavePressed), for: .touchDown)
        quickSaveButton.addTarget(self, action: #selector(self.quickSaveReleased), for: .touchUpInside)
        quickSaveButton.layer.borderColor = UIColor.white.cgColor
        quickSaveButton.layer.borderWidth = CGFloat(1)
        quickSaveButton.alpha = 0
        quickSaveButton.isHidden = true

        quickLoadButton = UIButton(type: .custom)
        quickLoadButton.setTitle(" QL ", for: .normal)
        quickLoadButton.addTarget(self, action: #selector(self.quickLoadPressed), for: .touchDown)
        quickLoadButton.addTarget(self, action: #selector(self.quickLoadReleased), for: .touchUpInside)
        quickLoadButton.layer.borderColor = UIColor.white.cgColor
        quickLoadButton.layer.borderWidth = CGFloat(1)
        quickLoadButton.alpha = 0
        quickLoadButton.isHidden = true

        
//        buttonStack = UIStackView(frame: CGRect(x: 20, y: 20, width: 30, height: 300))
        buttonStack = UIStackView(frame: .zero)
        buttonStack.frame.origin = CGPoint(x: 50, y: 50)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8.0
        buttonStack.alignment = .leading
        buttonStack.addArrangedSubview(expandButton)
//        buttonStack.addArrangedSubview(tildeButton)
        buttonStack.addArrangedSubview(escapeButton)
        buttonStack.addArrangedSubview(quickSaveButton)
        buttonStack.addArrangedSubview(quickLoadButton)

        return buttonStack
        
    }
    
    @objc func f1Button(rect: CGRect) -> UIButton {
        f1Button = UIButton(frame: CGRect(x: rect.width - 40, y: 10, width: 30, height: 30))
        f1Button.setTitle(" F1 ", for: .normal)
        f1Button.addTarget(self, action: #selector(self.f1Pressed), for: .touchDown)
        f1Button.addTarget(self, action: #selector(self.f1Released), for: .touchUpInside)
        f1Button.layer.borderColor = UIColor.white.cgColor
        f1Button.layer.borderWidth = CGFloat(1)
        f1Button.alpha = 0.5
        return f1Button
    }
    
    @objc func prevWeaponButton(rect: CGRect) -> UIButton {
        prevWeaponButton = UIButton(frame: CGRect(x: (rect.width / 3), y: rect.height/2, width: (rect.width / 3), height: rect.height/2))
        prevWeaponButton.addTarget(self, action: #selector(self.prevWeaponPressed), for: .touchDown)
        prevWeaponButton.addTarget(self, action: #selector(self.prevWeaponReleased), for: .touchUpInside)
        return prevWeaponButton
    }
    
    @objc func nextWeaponButton(rect: CGRect) -> UIButton {
        nextWeaponButton = UIButton(frame: CGRect(x: (rect.width / 3), y: 0, width: (rect.width / 3), height: rect.height/2))
        nextWeaponButton.addTarget(self, action: #selector(self.nextWeaponPressed), for: .touchDown)
        nextWeaponButton.addTarget(self, action: #selector(self.nextWeaponReleased), for: .touchUpInside)
        return nextWeaponButton
    }
    
    @objc func dpadView(rect: CGRect) -> UIView {
        // Create a container for the D-pad, moved higher up
        dpadView = UIView(frame: CGRect(x: 20, y: rect.height - 220, width: 160, height: 160))  // Moved up from -180 to -220
        
        let buttonSize: CGFloat = 55  // Increased from 50 to 55
        let centerX = dpadView.bounds.width / 2
        let centerY = dpadView.bounds.height / 2 - 15  // Shifted up by 15 points
        let spacing: CGFloat = 58  // Increased to account for larger buttons
        
        // Up button
        dpadUpButton = UIButton(frame: CGRect(x: centerX - buttonSize/2, y: centerY - spacing - buttonSize/2, width: buttonSize, height: buttonSize))
        dpadUpButton.setTitle("▲", for: .normal)
        dpadUpButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)  // Larger arrow
        dpadUpButton.layer.borderColor = UIColor.white.cgColor
        dpadUpButton.layer.borderWidth = 1
        dpadUpButton.alpha = 0.5
        dpadUpButton.addTarget(self, action: #selector(dpadUpPressed), for: .touchDown)
        dpadUpButton.addTarget(self, action: #selector(dpadUpReleased), for: .touchUpInside)
        dpadView.addSubview(dpadUpButton)
        
        // Down button
        dpadDownButton = UIButton(frame: CGRect(x: centerX - buttonSize/2, y: centerY + spacing - buttonSize/2, width: buttonSize, height: buttonSize))
        dpadDownButton.setTitle("▼", for: .normal)
        dpadDownButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)  // Larger arrow
        dpadDownButton.layer.borderColor = UIColor.white.cgColor
        dpadDownButton.layer.borderWidth = 1
        dpadDownButton.alpha = 0.5
        dpadDownButton.addTarget(self, action: #selector(dpadDownPressed), for: .touchDown)
        dpadDownButton.addTarget(self, action: #selector(dpadDownReleased), for: .touchUpInside)
        dpadView.addSubview(dpadDownButton)
        
        // Left button
        dpadLeftButton = UIButton(frame: CGRect(x: centerX - spacing - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize))
        dpadLeftButton.setTitle("◀", for: .normal)
        dpadLeftButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)  // Larger arrow
        dpadLeftButton.layer.borderColor = UIColor.white.cgColor
        dpadLeftButton.layer.borderWidth = 1
        dpadLeftButton.alpha = 0.5
        dpadLeftButton.addTarget(self, action: #selector(dpadLeftPressed), for: .touchDown)
        dpadLeftButton.addTarget(self, action: #selector(dpadLeftReleased), for: .touchUpInside)
        dpadView.addSubview(dpadLeftButton)
        
        // Right button
        dpadRightButton = UIButton(frame: CGRect(x: centerX + spacing - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize))
        dpadRightButton.setTitle("▶", for: .normal)
        dpadRightButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)  // Larger arrow
        dpadRightButton.layer.borderColor = UIColor.white.cgColor
        dpadRightButton.layer.borderWidth = 1
        dpadRightButton.alpha = 0.5
        dpadRightButton.addTarget(self, action: #selector(dpadRightPressed), for: .touchDown)
        dpadRightButton.addTarget(self, action: #selector(dpadRightReleased), for: .touchUpInside)
        dpadView.addSubview(dpadRightButton)
        
        dpadView.isHidden = true  // Start hidden
        return dpadView
    }

    @objc func enterButton(rect: CGRect) -> UIButton {
        // Move enter button closer to the center
        enterButton = UIButton(frame: CGRect(x: rect.width - 200, y: rect.height - 110, width: 75, height: 75))  // Changed y from -90 to -110
        enterButton.setTitle("ENTER", for: .normal)
        enterButton.setBackgroundImage(UIImage(named: "JoyStickBase"), for: .normal)
        enterButton.alpha = 0.5
        enterButton.addTarget(self, action: #selector(enterPressed), for: .touchDown)
        enterButton.addTarget(self, action: #selector(enterReleased), for: .touchUpInside)
        enterButton.isHidden = true  // Start hidden
        return enterButton
    }

    @objc func backButton(rect: CGRect) -> UIButton {
        // Move back button closer to enter button
        backButton = UIButton(frame: CGRect(x: rect.width - 110, y: rect.height - 140, width: 75, height: 75))  // Changed y from -120 to -140
        backButton.setTitle("BACK", for: .normal)
        backButton.setBackgroundImage(UIImage(named: "JoyStickBase"), for: .normal)
        backButton.alpha = 0.5
        backButton.addTarget(self, action: #selector(backPressed), for: .touchDown)
        backButton.addTarget(self, action: #selector(backReleased), for: .touchUpInside)
        backButton.isHidden = true  // Start hidden
        return backButton
    }
    
    @objc func quitButton(rect: CGRect) -> UIButton {
        let button = UIButton(frame: CGRect(x: 10, y: 10, width: 30, height: 30))  // Top left, same size as F1
        button.setTitle("Q", for: .normal)
        button.addTarget(self, action: #selector(self.quitPressed), for: .touchDown)
        button.layer.borderColor = UIColor.white.cgColor
        button.layer.borderWidth = CGFloat(1)
        button.alpha = 0.5
        // Remove the red background
        
        self.quitButton = button
        return button
    }
    
    @objc func isConsoleVisible() -> Bool {
        // The console is visible if cls.key_dest is key_console OR if we're disconnected
        let keyDest = cls.key_dest
        let inConsole = (keyDest == keydest_t(1))
        let disconnected = (cls.state == connstate_t(1))  // ca_disconnected is usually 1
        
        return inConsole || disconnected
    }
    
    @objc func quitPressed(sender: UIButton!) {
        if isConsoleVisible() {
            print("Console is visible - toggling console")
            "toggleconsole\n".withCString { ptr in
                Cbuf_AddText(UnsafeMutablePointer(mutating: ptr))
            }
        } else {
            print("In game - disconnecting")
            "disconnect\n".withCString { ptr in
                Cbuf_AddText(UnsafeMutablePointer(mutating: ptr))
            }
        }
    }
    
    @objc func updateControlsVisibility() {
        // Check game state using cls.key_dest
        let keyDest = cls.key_dest
        let inGame = (keyDest == keydest_t(0))      // key_game is 0
        let inMenu = (keyDest == keydest_t(3))      // key_menu is 3
        let inConsole = (keyDest == keydest_t(1))   // key_console is 1
        
        // Update Q button text based on state
        if isConsoleVisible() {
            quitButton.setTitle("Q", for: .normal)  // Tilde is the console key, but leave as Q
        } else {
            quitButton.setTitle("Q", for: .normal)
        }
        
        // Hide all controls if console is active
        if inConsole {
            fireButton.isHidden = true
            joystickView.isHidden = true
            rightJoystickView.isHidden = true
            prevWeaponButton.isHidden = true
            nextWeaponButton.isHidden = true
            quitButton.isHidden = false
            quitButton.isHidden = true
            dpadView.isHidden = true
            enterButton.isHidden = true
            backButton.isHidden = true
            return
        }
        
        // Show/hide based on menu vs game
        if inMenu {
            // Hide game controls
            fireButton.isHidden = true
            joystickView.isHidden = true
            rightJoystickView.isHidden = true
            prevWeaponButton.isHidden = true
            nextWeaponButton.isHidden = true
            quitButton.isHidden = true
            
            // Show menu controls
            dpadView.isHidden = false
            enterButton.isHidden = false
            backButton.isHidden = false
        } else if inGame {
            // Show game controls
            fireButton.isHidden = false
            joystickView.isHidden = false
            rightJoystickView.isHidden = false
            prevWeaponButton.isHidden = false
            nextWeaponButton.isHidden = false
            
            #if USE_IOS_GAMECONTROLLER
            quitButton.isHidden = iOS_IsControllerConnected()
            #else
            quitButton.isHidden = false
            #endif
            
            // Hide menu controls
            dpadView.isHidden = true
            enterButton.isHidden = true
            backButton.isHidden = true
        }
    }

    
    @objc func firePressed(sender: UIButton!) {
        Key_Event(137, qboolean(1), qboolean(1))
    }
    
    @objc func fireReleased(sender: UIButton!) {
        Key_Event(137, qboolean(0), qboolean(1))
    }
    
    @objc func jumpPressed(sender: UIButton!) {
        Key_Event(32, qboolean(1), qboolean(1))
    }
    
    @objc func jumpReleased(sender: UIButton!) {
        Key_Event(32, qboolean(0), qboolean(1))
    }
    
    @objc func tildePressed(sender: UIButton!) {
//        Key_Event(32, qboolean(1), qboolean(1))
    }
    
    @objc func tildeReleased(sender: UIButton!) {
//        Key_Event(32, qboolean(0), qboolean(1))
    }
    
    @objc func escapePressed(sender: UIButton!) {
        Key_Event(27, qboolean(1), qboolean(1))
    }
    
    @objc func escapeReleased(sender: UIButton!) {
        Key_Event(27, qboolean(0), qboolean(1))
    }
    
    @objc func quickSavePressed(sender: UIButton!) {
        Key_Event(150, qboolean(1), qboolean(1))
    }
    
    @objc func quickSaveReleased(sender: UIButton!) {
        Key_Event(150, qboolean(0), qboolean(1))
    }
    
    @objc func quickLoadPressed(sender: UIButton!) {
        Key_Event(153, qboolean(1), qboolean(1))
    }
    
    @objc func quickLoadReleased(sender: UIButton!) {
        Key_Event(153, qboolean(0), qboolean(1))
    }
    
    @objc func f1Pressed(sender: UIButton!) {
        Key_Event(145, qboolean(1), qboolean(1))
    }
    
    @objc func f1Released(sender: UIButton!) {
        Key_Event(145, qboolean(0), qboolean(1))
    }
    
    @objc func prevWeaponPressed(sender: UIButton!) {
        Key_Event(183, qboolean(1), qboolean(1))
    }
    
    @objc func prevWeaponReleased(sender: UIButton!) {
        Key_Event(183, qboolean(0), qboolean(1))
    }
    
    @objc func nextWeaponPressed(sender: UIButton!) {
        Key_Event(184, qboolean(1), qboolean(1))
    }
    
    @objc func nextWeaponReleased(sender: UIButton!) {
        Key_Event(184, qboolean(0), qboolean(1))
    }
    
    @objc func dpadUpPressed() {
        Key_Event(132, qboolean(1), qboolean(1))  // Up arrow
    }

    @objc func dpadUpReleased() {
        Key_Event(132, qboolean(0), qboolean(1))
    }

    @objc func dpadDownPressed() {
        Key_Event(133, qboolean(1), qboolean(1))  // Down arrow
    }

    @objc func dpadDownReleased() {
        Key_Event(133, qboolean(0), qboolean(1))
    }

    @objc func dpadLeftPressed() {
        Key_Event(134, qboolean(1), qboolean(1))  // Left arrow
    }

    @objc func dpadLeftReleased() {
        Key_Event(134, qboolean(0), qboolean(1))
    }

    @objc func dpadRightPressed() {
        Key_Event(135, qboolean(1), qboolean(1))  // Right arrow
    }

    @objc func dpadRightReleased() {
        Key_Event(135, qboolean(0), qboolean(1))
    }

    @objc func enterPressed() {
        Key_Event(13, qboolean(1), qboolean(1))  // Enter key
    }

    @objc func enterReleased() {
        Key_Event(13, qboolean(0), qboolean(1))
    }

    @objc func backPressed() {
        Key_Event(27, qboolean(1), qboolean(1))  // Escape key
    }

    @objc func backReleased() {
        Key_Event(27, qboolean(0), qboolean(1))
    }


    @objc func expand(_ sender: Any) {
        buttonStackExpanded = !buttonStackExpanded
        
        UIView.animate(withDuration: 0.5) {
            self.expandButton.setTitle(self.buttonStackExpanded ? " < " : " > ", for: .normal)
            self.expandButton.alpha = self.buttonStackExpanded ? 1 : 0.5
            self.escapeButton.isHidden = !self.buttonStackExpanded
            self.escapeButton.alpha = self.buttonStackExpanded ? 1 : 0
            self.tildeButton.isHidden = !self.buttonStackExpanded
            self.tildeButton.alpha = self.buttonStackExpanded ? 1 : 0
            self.quickLoadButton.isHidden = !self.buttonStackExpanded
            self.quickLoadButton.alpha = self.buttonStackExpanded ? 1 : 0
            self.quickSaveButton.isHidden = !self.buttonStackExpanded
            self.quickSaveButton.alpha = self.buttonStackExpanded ? 1 : 0
        }
        
    }
    
}

extension SDL_uikitviewcontroller: JoystickDelegate {
    
    func handleJoyStickPosition(sender: JoyStickView, x: CGFloat, y: CGFloat) {
        // Smaller deadzone as requested
        let deadzone: CGFloat = 0.08  // Reduced from 0.15
        
        // Apply deadzone
        var adjustedX = x
        var adjustedY = y
        let magnitude = sqrt(x * x + y * y)
        
        if magnitude < deadzone {
            adjustedX = 0
            adjustedY = 0
        } else {
            // Scale from deadzone to 1.0
            let scaledMagnitude = (magnitude - deadzone) / (1.0 - deadzone)
            adjustedX = (x / magnitude) * scaledMagnitude
            adjustedY = (y / magnitude) * scaledMagnitude
        }
        
        if sender.tag == 2 {
            // RIGHT JOYSTICK - Direct analog control like gamepad
            let sensitivity: CGFloat = 1.5  // Inrease for faster looking
            let acceleration: CGFloat = 2.3
            
            // Apply acceleration curve
            let xSign: CGFloat = adjustedX < 0 ? -1.0 : 1.0
            let ySign: CGFloat = adjustedY < 0 ? -1.0 : 1.0
            let accelX = xSign * pow(abs(adjustedX), acceleration)
            let accelY = ySign * pow(abs(adjustedY), acceleration)
            
            // Set analog values directly like gamepad
            joystick_yaw = Float(accelX * sensitivity)
            
            // FIX Y-AXIS: Remove the negative sign! Positive Y = look down
            joystick_pitch = Float(accelY * sensitivity)  // NO NEGATIVE!
            
        } else {
            // LEFT JOYSTICK - Direct analog control
            let moveSensitivity: CGFloat = 1.5  // Add this for movement sensitivity
                
            joystick_sidemove = Float(adjustedX * moveSensitivity)
            joystick_forwardmove = Float(-adjustedY * moveSensitivity) // -Y for inverted axis
        }
    }
    
    func handleJoyStick(sender: JoyStickView, angle: CGFloat, displacement: CGFloat) {
        // Unused but required by protocol
    }
}
