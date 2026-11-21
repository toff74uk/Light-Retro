#import <XCTest/XCTest.h>
#include "../../LightRetro/Emulation/CoreOptions.hpp"

@interface CoreOptionsTests : XCTestCase
@end

@implementation CoreOptionsTests
- (void)testLegacyDefinitionsReplaceAndValidateSavedChoices {
    CoreOptions options;
    retro_variable first[] = {{"difficulty", "Difficulty; Normal|Hard"}, {"region", "Region; Auto|Japan"}, {}};
    options.replace(first);
    XCTAssertTrue(options.definitions.at("difficulty").value == "Normal");
    XCTAssertFalse(options.set("difficulty", "Easy"));
    XCTAssertFalse(options.changed);
    XCTAssertTrue(options.set("difficulty", "Hard"));
    XCTAssertTrue(options.changed);

    retro_core_option_v2_definition updated[2]{};
    updated[0].key = "difficulty";
    updated[0].desc = "Difficulty";
    updated[0].values[0] = {"Normal", "Standard"};
    updated[0].values[1] = {"Hard", "Expert"};
    updated[0].default_value = "Normal";
    options.replace(updated);
    XCTAssertEqual(options.definitions.size(), 1u);
    XCTAssertTrue(options.definitions.at("difficulty").value == "Hard");
    XCTAssertTrue(options.definitions.at("difficulty").choices[1].second == "Expert");

    retro_core_option_definition next[2]{};
    next[0].key = "difficulty";
    next[0].values[0].value = "0";
    next[0].values[1].value = "1";
    next[0].default_value = "1";
    options.replace(next);
    XCTAssertTrue(options.definitions.at("difficulty").value == "1");
    options.replace(static_cast<const retro_variable*>(nullptr));
    XCTAssertTrue(options.definitions.empty());
}
@end
