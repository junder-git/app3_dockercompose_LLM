import { handleLogin, handleRegister, verifyToken, handleAdminRequest } from './auth.js';
import { handleInitEndpoint } from './init.js';
import { healthCheck } from './utils.js';
import { getModelList, getModelDetails } from './models.js';

export default {
  async login(r) {
    await handleLogin(r);
  },

  async register(r) {
    await handleRegister(r);
  },

  async verify(r) {
    await verifyToken(r);
  },

  async init(r) {
    await handleInitEndpoint(r);
  },

  async admin(r) {
    await handleAdminRequest(r);
  },

  async health(r) {
    await healthCheck(r);
  },

  async modelList(r) {
    await getModelList(r);
  },

  async modelDetails(r) {
    await getModelDetails(r);
  }
};
