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
  static const secureAccount = '/you/secure';
  static const requestHistory = '/you/history/requests';
  static const donationHistory = '/you/history/donations';
  static const privacy = '/you/privacy';
  static const settings = '/you/settings';

  // Admin Routes
  static const adminLogin = '/admin/login';
  static const adminNoAccess = '/admin/no-access';
  static const adminDashboard = '/admin';
  static const adminUsers = '/admin/users';
  static const adminDonors = '/admin/donors';
  static const adminVerification = '/admin/verification';
  static const adminRequests = '/admin/requests';
  static const adminEmergency = '/admin/emergency';
  static const adminDonations = '/admin/donations';
  static const adminConnections = '/admin/connections';
  static const adminHospitals = '/admin/hospitals';
  static const adminAnalytics = '/admin/analytics';
  static const adminNotifications = '/admin/notifications';
  static const adminReports = '/admin/reports';
  static const adminModeration = '/admin/moderation';
  static const adminAudit = '/admin/audit';
  static const adminHealth = '/admin/health';
  static const adminSettings = '/admin/settings';
  static const adminLiveMap = '/admin/map';
  static const adminAvailability = '/admin/availability';
}
