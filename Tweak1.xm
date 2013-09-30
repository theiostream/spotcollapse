// SpotlightUI
// Ariel insisted a lot on this, and the idea ended up to be quite cool.

#import <SearchLoader/TLLibrary.h>
#import <QuartzCore/QuartzCore.h>

@interface UIDevice (TLExtension)
- (BOOL)isWildcat;
@end
#define isiPad() ([UIDevice instancesRespondToSelector:@selector(isWildcat)] && [[UIDevice currentDevice] isWildcat])

#define MAX_VISIBLE_CELLS 7

// Global associated object keys
static char gestureRecognizerKey;
static char appRecognizerKey;

// Global arrays
static bool *collapsed_sections = NULL;
static int *section_index = NULL;
static float *footer_height = NULL;
static int global_size = 0;

static BOOL global_default_collapsed = NO;
static BOOL collapse_one = NO;
static BOOL global_check = NO;

static void UpdatePrefs() {
	NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/am.theiostre.spotlightplus.extension.plist"];
	if (!plist) return;

	NSNumber *coll = [plist objectForKey:@"CollapseDefault"];
	global_default_collapsed = coll ? [coll boolValue] : NO;
	
	NSNumber *one = [plist objectForKey:@"CollapseOne"];
	collapse_one = one ? [one boolValue] : NO;
}
static void ReloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	UpdatePrefs();
}


// Class Definitions
@interface SBApplication : NSObject
- (NSString *)displayName;
@end

@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (SBApplication *)applicationWithDisplayIdentifier:(NSString *)identifier;
@end

@interface SBUIController : NSObject
+ (id)sharedInstance;
- (void)activateApplicationAnimated:(SBApplication *)app;
@end

/*@interface SPSearchResultSection : NSObject
- (BOOL)hasDomain;
- (int)domain;
- (NSString *)displayIdentifier;
@end*/

@interface SBSearchModel : NSObject
+ (id)sharedInstance;
- (SPSearchResultSection *)sectionAtIndex:(int)index;
@end

@interface SBSearchTableViewCell : UITableViewCell
- (void)setTitle:(NSString *)title;
- (void)setSubtitle:(NSString *)subtitle;
- (void)setSummary:(NSString *)summary;
- (void)setAuxiliarySubtitle:(NSString *)shit;
- (void)setAuxiliaryTitle:(NSString *)shit2;
- (void)setLastInTableView:(BOOL)last;
@end

@interface SBSearchView : UIView <UIGestureRecognizerDelegate>
- (UITableView *)tableView;
- (void)layoutCornerView;
@end

@interface SBSearchController : NSObject <UITableViewDelegate>
- (SBSearchView *)searchView;
@end

@interface SBIconController : NSObject
+ (id)sharedInstance;
- (SBSearchController *)searchController;
@end

static int CellCount(UITableView *tableView) {
	int ret = 0;
	int ns = [tableView numberOfSections];

	for (int i=0; i<ns; i++) {
		ret += [tableView numberOfRowsInSection:i];
	}

	return ret;
}

// Hooks
%hook SBSearchView
- (id)initWithFrame:(CGRect)frame withContent:(id)content onWallpaper:(id)wallpaper {
	if ((self = %orig)) {
		UITapGestureRecognizer *recognizer = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tl_tappedTableView:)] autorelease];
		[recognizer setDelegate:self];
		objc_setAssociatedObject(self, &gestureRecognizerKey, recognizer, OBJC_ASSOCIATION_RETAIN);
		
		UILongPressGestureRecognizer *appRecognizer = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_tl_tappedTableView:)] autorelease];
		[appRecognizer setDelegate:self];
		objc_setAssociatedObject(self, &appRecognizerKey, appRecognizer, OBJC_ASSOCIATION_RETAIN);

		[recognizer requireGestureRecognizerToFail:appRecognizer];
	}

	return self;
}

- (void)addTableView {
	%orig;
	[MSHookIvar<UITableView *>(self, "_tableView") addGestureRecognizer:objc_getAssociatedObject(self, &gestureRecognizerKey)];
	[MSHookIvar<UITableView *>(self, "_tableView") addGestureRecognizer:objc_getAssociatedObject(self, &appRecognizerKey)];
}

- (void)removeTableView {
	[MSHookIvar<UITableView *>(self, "_tableView") removeGestureRecognizer:objc_getAssociatedObject(self, &gestureRecognizerKey)];
	[MSHookIvar<UITableView *>(self, "_tableView") removeGestureRecognizer:objc_getAssociatedObject(self, &appRecognizerKey)];
	%orig;
}

%new(c@:@@)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
	UITableView *tableView = MSHookIvar<UITableView *>(self, "_tableView");
	CGPoint point = [touch locationInView:tableView];

	return ([tableView indexPathForRowAtPoint:point] && collapsed_sections[[[tableView indexPathForRowAtPoint:point] section]]) || point.x < (isiPad() ? 68 : 40);
}

%new(v@:@)
- (void)_tl_tappedTableView:(UIGestureRecognizer *)recognizer {
	%log;

	SBSearchController *controller = [[%c(SBIconController) sharedInstance] searchController];
	UITableView *tableView = MSHookIvar<UITableView *>(self, "_tableView");
	CGPoint point = [recognizer locationInView:tableView];
	
	NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:point];
	if (indexPath != nil) {
		int section = [indexPath section];
		
		if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
			SPSearchResultSection *sektion = [[%c(SBSearchModel) sharedInstance] sectionAtIndex:section];
			NSString *display = [sektion displayIdentifier];
			
			// TODO: We could add some sort of format key on the InfoPlugin's plist so it could get us an URL
			// to open the app on its search functionality thingies taking as the str format the query.
			SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithDisplayIdentifier:display];
			if (app != nil) [[%c(SBUIController) sharedInstance] activateApplicationAnimated:app];
		}
		
		else {
			if (section_index[section] < 2 && !collapse_one) return;
			
			UIView *tableFooterView = [tableView tableFooterView];
			
			collapsed_sections[section] = !collapsed_sections[section];
			NSMutableArray *rows = [NSMutableArray arrayWithCapacity:section_index[section]];
			for (int i=1; i<section_index[section]; i++) {
				NSIndexPath *path = [NSIndexPath indexPathForRow:i inSection:section];
				[rows addObject:path];
			}

			MSHookIvar<BOOL>(controller, "_reloadingTableContent") = YES;
			
			if (!collapsed_sections[section]) {
				int cells_count = CellCount(tableView);
				int new_count = cells_count - (section_index[section] - 1);
				if (new_count > [[tableView visibleCells] count]) {
					bzero(footer_height, global_size);
					[tableFooterView setFrame:(CGRect){tableFooterView.frame.origin, {tableFooterView.frame.size.width, 0.f}}];
				}
				
				else {
					[tableFooterView setFrame:(CGRect){tableFooterView.frame.origin, {tableFooterView.frame.size.width, tableFooterView.frame.size.height - footer_height[section]}}];
					footer_height[section] = 0.f;
				}
			}

			else {
				CGFloat height = section_index[section]==1 && isiPad() ? 72.f : 44.f;
				int cells_count = CellCount(tableView);
				NSLog(@"cells count = %d", cells_count);

				int new_count = cells_count - (section_index[section] - 1);
				NSLog(@"new_count = %d", new_count);
				if (new_count <= [[tableView visibleCells] count]) {
					NSLog(@"new_count less or equal to visible cells count (%d)", [[tableView visibleCells] count]);
					footer_height[section] = (height * (MAX_VISIBLE_CELLS - new_count)) - [tableFooterView frame].size.height;
					NSLog(@"footer_height[%d] = %f * %d = %f", section, height, (MAX_VISIBLE_CELLS - new_count), footer_height[section]);
					[tableFooterView setFrame:(CGRect){tableFooterView.frame.origin, {tableFooterView.frame.size.width, tableFooterView.frame.size.height + footer_height[section]}}];
					NSLog(@"footer view frame = %@", NSStringFromCGRect([tableFooterView frame]));
				}
				
				/*footer_height[section] = (section_index[section] - 1) * height;
				[tableFooterView setFrame:(CGRect){tableFooterView.frame.origin, {tableFooterView.frame.size.width, tableFooterView.frame.size.height + footer_height[section]}}];*/
			}

			[tableView beginUpdates];
			if (collapsed_sections[section])
				[tableView deleteRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
			else
				[tableView insertRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
			[tableView endUpdates];
			
			[UIView setAnimationsEnabled:NO];
			[tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:section]] withRowAnimation:UITableViewRowAnimationNone];
			[UIView setAnimationsEnabled:YES];

			//[tableView setFrame:tableFrame];
			
			/*[tableView beginUpdates];
			[tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:section]] withRowAnimation:UITableViewRowAnimationNone];
			[tableView endUpdates];*/
			
			MSHookIvar<BOOL>(controller, "_reloadingTableContent") = NO;

			// We need this workaround so we will get decent header views instead of a weird thing.
			NSInteger sectionNumber = [tableView numberOfSections];
			for (int i=0; i<sectionNumber; i++) {
				UITableViewHeaderFooterView *header = [tableView headerViewForSection:i];
				[controller tableView:tableView willDisplayHeaderView:header forSection:i];
			}
		}
	}
}

- (void)dealloc {
	objc_setAssociatedObject(self, &gestureRecognizerKey, nil, OBJC_ASSOCIATION_ASSIGN);
	objc_setAssociatedObject(self, &appRecognizerKey, nil, OBJC_ASSOCIATION_ASSIGN);
	%orig;
}
%end

%hook SBSearchController
- (id)init {
	if ((self = %orig)) {
		void *SearchResultDomainCount = dlsym(RTLD_DEFAULT, "SearchResultDomainCount");
		int domains = ((int(*)(void))SearchResultDomainCount)();

		collapsed_sections = (bool *)malloc(domains * sizeof(bool));
		section_index = (int *)malloc(domains * sizeof(int));
		footer_height = (float *)malloc(domains * sizeof(float));

		global_size = domains;
	}

	return self;
}

- (int)tableView:(UITableView *)tableView numberOfRowsInSection:(int)section {
	int rows = %orig;
	section_index[section] = rows;
	
	if (collapsed_sections[section] && !global_check) return 1;
	return rows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SBSearchTableViewCell *cell = (SBSearchTableViewCell *)%orig;

	if (collapsed_sections[[indexPath section]]) {
		if (section_index[[indexPath section]] < 2 && !collapse_one) {
			return cell;
		}
		
		SPSearchResultSection *section = [[%c(SBSearchModel) sharedInstance] sectionAtIndex:[indexPath section]];
		NSString *displayIdentifier = [section displayIdentifier];
		SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithDisplayIdentifier:displayIdentifier];
		
		__block NSString *name;
		if (app == nil) {
			TLIterateExtensions(^(NSString *path){
				NSDictionary *infoDictionary = [[NSBundle bundleWithPath:path] infoDictionary];
				if ([[infoDictionary objectForKey:@"SPDisplayIdentifier"] isEqualToString:displayIdentifier]) {
					name = [infoDictionary objectForKey:@"TLDisplayName"] ?: displayIdentifier;
				}
			});
		}
		else name = [app displayName];

		[cell setTitle:[name stringByAppendingString:@" Search"]];
		[cell setSummary:nil];
		[cell setSubtitle:nil];
		[cell setAuxiliaryTitle:nil];
		[cell setAuxiliarySubtitle:nil];

	}

	if ([indexPath section] == [tableView numberOfSections]-1 && [indexPath row] == (collapsed_sections[[indexPath section]] ? 0 : 1)) {
		NSLog(@"height %f fh %f", [[tableView tableFooterView] frame].size.height, footer_height[[indexPath section]]);

		if ([[tableView tableFooterView] frame].size.height == 0.f && footer_height[[indexPath section]] == 0.f)
			[cell setLastInTableView:YES];
		else
			[cell setLastInTableView:NO]; // we don't got a footer.
	}
	
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (isiPad() && collapsed_sections[[indexPath section]]) return 72.f;
	return %orig;
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
	NSLog(@"global_default_collapsed = %d", global_default_collapsed);
	memset(collapsed_sections, global_default_collapsed ? 1 : 0, global_size);
	bzero(section_index, global_size);
	bzero(footer_height, global_size);
	
	%orig;
}

- (void)dealloc {
	free(collapsed_sections);
	free(section_index);

	%orig;
}
%end

%ctor {
	%init;

	UpdatePrefs();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, &ReloadPrefs, CFSTR("am.theiostre.spotlightplus.extension.notification"), NULL, 0);
}
