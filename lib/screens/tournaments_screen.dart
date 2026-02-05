import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tournament_join_screen.dart';
import 'tournament_dashboard_screen.dart';
import 'my_tournaments_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  void _showWeeklyTournamentsDialog(BuildContext context, String parentTournamentId, String parentName) async {
    try {
      // Get all weekly tournaments for this parent
      final weeklyTournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('parentTournamentId', isEqualTo: parentTournamentId)
          .get();

      if (!context.mounted) return;

      // Sort client-side by date
      final weeklyTournaments = weeklyTournamentsSnapshot.docs;
      weeklyTournaments.sort((a, b) {
        final aDate = (a.data())['date'] as String? ?? '';
        final bDate = (b.data())['date'] as String? ?? '';
        return aDate.compareTo(bDate);
      });

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$parentName - Weekly Tournaments'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: weeklyTournaments.isEmpty
                ? const Center(
                    child: Text('No weekly tournaments yet.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: weeklyTournaments.length,
                    itemBuilder: (context, index) {
                      final doc = weeklyTournaments[index];
                      final data = doc.data();
                      final name = data['name'] as String? ?? 'Week ${index + 1}';
                      final date = data['date'] as String? ?? '';
                      final status = data['status'] as String? ?? 'upcoming';
                      final tournamentNumber = data['tournamentNumber'] as int?;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: status == 'completed' ? Colors.green : Colors.orange,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                date.isNotEmpty ? date : name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            if (tournamentNumber != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$tournamentNumber',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Icon(
                              status == 'completed' ? Icons.check_circle : Icons.pending,
                              size: 12,
                              color: status == 'completed' ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(status.toUpperCase(), style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status != 'completed')
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TournamentJoinScreen(
                                        tournamentId: doc.id,
                                        tournamentName: name,
                                        tournamentImageUrl: data['imageUrl'] as String?,
                                      ),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  minimumSize: const Size(55, 32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.login, size: 18),
                                    SizedBox(width: 6),
                                    Text('Join', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TournamentDashboardScreen(
                                      tournamentId: doc.id,
                                      tournamentName: name,
                                    ),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                minimumSize: const Size(70, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.leaderboard, size: 18),
                                  SizedBox(width: 6),
                                  Text('Results', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TournamentDashboardScreen(
                      tournamentId: parentTournamentId,
                      tournamentName: parentName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.emoji_events),
              label: const Text('Overall Standings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading weekly tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to build asset image with proper path handling
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width ?? 60,
        height: height ?? 60,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A8A).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.emoji_events,
          color: Color(0xFF1E3A8A),
          size: 32,
        ),
      );
    }

    // Normalize the path - ensure it starts with 'assets/'
    String normalizedPath = imagePath.trim();
    
    // Remove leading slash if present
    if (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }
    
    // Ensure it starts with 'assets/'
    if (!normalizedPath.startsWith('assets/')) {
      // If it starts with 'images/', add 'assets/' prefix
      if (normalizedPath.startsWith('images/')) {
        normalizedPath = 'assets/$normalizedPath';
      } else {
        // Otherwise, assume it's in assets/images/
        normalizedPath = 'assets/images/$normalizedPath';
      }
    }
    
    return Image.asset(
      normalizedPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Failed to load asset image: $normalizedPath');
        debugPrint('Original path: $imagePath');
        debugPrint('Error: $error');
        return Container(
          width: width ?? 60,
          height: height ?? 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.emoji_events,
            color: Color(0xFF1E3A8A),
            size: 32,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppHeader(
        title: 'Tournaments',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'My Tournaments',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyTournamentsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const AppFooter(selectedIndex: 2),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tour, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No tournaments available',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check back later for upcoming tournaments',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Filter out archived tournaments (isArchived == true) and sort by date
          final tournaments = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isArchived = data['isArchived'] as bool? ?? false;
            return !isArchived;
          }).toList();
          
          // Sort by date (if available), then by name
          tournaments.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aDate = aData['date'] as String? ?? '';
            final bDate = bData['date'] as String? ?? '';
            
            if (aDate.isNotEmpty && bDate.isNotEmpty) {
              return aDate.compareTo(bDate);
            } else if (aDate.isNotEmpty) {
              return -1; // Dates first
            } else if (bDate.isNotEmpty) {
              return 1;
            }
            // If no dates, sort by name
            final aName = aData['name'] as String? ?? '';
            final bName = bData['name'] as String? ?? '';
            return aName.compareTo(bName);
          });

          if (tournaments.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tour, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No active tournaments available',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check back later for upcoming tournaments',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tournaments.length,
            itemBuilder: (context, index) {
              final doc = tournaments[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] as String? ?? 'Unknown Tournament';
              final description = data['description'] as String? ?? '';
              final imageUrl = data['imageUrl'] as String?;
              final date = data['date'] as String?;
              final tournamentNumber = data['tournamentNumber'] as int?;
              final isParentTournament = data['isParentTournament'] as bool? ?? false;
              final parentTournamentId = data['parentTournamentId'] as String?;
              final isHidden = data['hidden'] as bool? ?? false;
              
              // Skip weekly tournaments in main list (they'll be shown under parent)
              if (parentTournamentId != null) {
                return const SizedBox.shrink();
              }
              
              // Skip hidden tournaments (but don't archive them)
              if (isHidden) {
                return const SizedBox.shrink();
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: index % 2 == 0
                        ? [const Color(0xFF6B46C1), const Color(0xFFFFC400)]
                        : [const Color(0xFF1E3A8A), const Color(0xFF6B46C1)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    // If parent tournament, show weekly tournaments list
                    if (isParentTournament) {
                      _showWeeklyTournamentsDialog(context, doc.id, name);
                    } else {
                      // Regular tournament - go to join screen
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TournamentJoinScreen(
                            tournamentId: doc.id,
                            tournamentName: name,
                            tournamentImageUrl: imageUrl,
                          ),
                        ),
                      );
                    }
                  },
                  onLongPress: () {
                    // Long press to open dashboard
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TournamentDashboardScreen(
                          tournamentId: doc.id,
                          tournamentName: name,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl.startsWith('http')
                                    ? Image.network(
                                        imageUrl,
                                        width: 100,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 60,
                                            height: 60,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.emoji_events,
                                              color: Color(0xFF1E3A8A),
                                              size: 32,
                                            ),
                                          );
                                        },
                                      )
                                    : _buildAssetImage(imageUrl, width: 100, height: 60),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E3A8A).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.emoji_events,
                                  color: Color(0xFF1E3A8A),
                                  size: 32,
                                ),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (tournamentNumber != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '#$tournamentNumber',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (date != null && date.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          date,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.9),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF1E3A8A),
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E3A8A),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isParentTournament ? 'View Weekly Tournaments' : 'Join Tournament',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => TournamentDashboardScreen(
                                      tournamentId: doc.id,
                                      tournamentName: name,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green[600],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.leaderboard,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isParentTournament 
                              ? 'Tap to view weekly tournaments • Tap 📊 for overall standings' 
                              : 'Tap to join • Tap 📊 for results',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
