import {
  NativeModules,
  NativeEventEmitter
} from 'react-native';

const { RNTwilio } = NativeModules;

const _eventEmitter = new NativeEventEmitter(RNTwilio);

const _eventHandlers = {
  incomingCall: new Map(),
  incomingCallCancelled: new Map(),
  deviceRegistered: new Map(),
  deviceNotRegistered: new Map(),
  connectionDidConnect: new Map(),
  connectionDidDisconnect: new Map(),
  connectionDidFail: new Map(),
  connectionDidStartRinging: new Map(),
  connectionIsReconnecting: new Map(),
  connectionDidReconnect: new Map(),
  callWasRejected: new Map()
}

const Twilio = {
  initializeWithToken(token) {
    if (typeof token !== 'string' || token == "") {
      return {
        initialized: false,
        err: "Invalid token, please try again."
      }
    }
    return RNTwilio.initializeWithToken(token);
  },

  initializeWithTokenAndBaseURL(twilioToken, freedomSoftToken, baseURL) {
    if (typeof twilioToken !== 'string' || twilioToken == "") {
      return {
        initialized: false,
        err: "Invalid token, please try again."
      }
    }

    if (typeof freedomSoftToken !== 'string' || freedomSoftToken == "") {
      return {
        initialized: false,
        err: "Invalid freedomsoft session token, please try again."
      }
    }

    if (typeof baseURL !== 'string' || baseURL == "") {
      return {
        initialized: false,
        err: "Invalid base url, please try again."
      }
    }
    return RNTwilio.initializeWithTokenAndBaseURL(twilioToken, freedomSoftToken, baseURL);
  },

  logout() {
    RNTwilio.logout();
  },

  makePhoneCall(params = {}) {
    RNTwilio.makePhoneCall(params);
  },

  disconnectActiveCall() {
    RNTwilio.disconnectActiveCall();
  },

  acceptIncomingCall() {
    RNTwilio.acceptIncomingCall();
  },

  rejectIncomingCall() {
    RNTwilio.rejectIncomingCall();
  },

  getActiveCall() {
    return RNTwilio.getActiveCall();
  },

  setSpeakerPhone(value) {
    RNTwilio.setSpeakerPhone(value)
  },

  sendDtmf(dtmf) {
    RNTwilio.sendDtmf(dtmf)
  },
  
  setMute(value) {
    RNTwilio.setMute(value)
  },

  checkIsCallInProgressWhenOpeningAppFromBackground() {
    RNTwilio.checkIsCallInProgressWhenOpeningAppFromBackground();
  },

  addEventListener(type, handler) {
    if (_eventHandlers[type].has(handler)) {
      return;
    }
    _eventHandlers[type].set(handler, _eventEmitter.addListener(type, func => { handler(func) }));
  },

  removeEventListener(type, handler) {
    if (!_eventHandlers[type].has(handler)) {
      return;
    }
    _eventHandlers[type].get(handler).remove();
    _eventHandlers[type].delete(handler);
  }
}

export default Twilio;