/// Route path + name constants. Kept in one place so navigation calls never
/// pass around raw strings.
abstract class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const onboarding = '/onboarding';

  static const home = '/home';
  static const notifications = '/notifications';

  static const requests = '/requests';
  static const createRequest = '/requests/create';
  // request detail/tracking: '/requests/:id'
  static String requestDetail(String id) => '/requests/$id';
  // coordination: '/requests/:id/coordination'
  static String coordination(String id) => '/requests/$id/coordination';
  static String chat(String id) => '/requests/$id/chat';
  static String liveLocation(String id) => '/requests/$id/location';

  static const invitations = '/invitations';
  static String invitationDetail(String id) => '/invitations/$id';

  static const donate = '/donate';
  static const donorSettings = '/donate/settings';

  static const you = '/you';
  static const profileEdit = '/you/profile';
  static const requestHistory = '/you/history/requests';
  static const donationHistory = '/you/history/donations';
  static const privacy = '/you/privacy';
  static const settings = '/you/settings';
}
