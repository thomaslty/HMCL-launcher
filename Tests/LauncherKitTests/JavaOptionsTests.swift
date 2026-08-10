import Testing

@testable import LauncherKit

@Suite struct JavaOptionsTests {
    @Test func splitsOnWhitespace() {
        #expect(JavaOptions.parse("-Xmx4G -Dfoo=bar") == ["-Xmx4G", "-Dfoo=bar"])
    }

    @Test func collapsesRunsOfWhitespace() {
        #expect(JavaOptions.parse("  -Xmx4G \t\n -Xms1G  ") == ["-Xmx4G", "-Xms1G"])
    }

    @Test func emptyTextGivesNothing() {
        #expect(JavaOptions.parse("").isEmpty)
        #expect(JavaOptions.parse("   \t \n ").isEmpty)
    }

    @Test func doubleQuotesKeepSpacesInOneArgument() {
        #expect(JavaOptions.parse("-Dname=\"two words\"") == ["-Dname=two words"])
    }

    @Test func singleQuotesWorkTheSameWay() {
        #expect(JavaOptions.parse("-Dname='two words'") == ["-Dname=two words"])
    }

    @Test func quotedSectionJoinsWhatFollowsIt() {
        // Matches HMCL's own parser: quotes group, they do not delimit.
        #expect(JavaOptions.parse("\"a b\"c") == ["a bc"])
    }

    @Test func unmatchedQuoteTakesTheRestLiterally() {
        // The field is edited live, so a half-typed quote must not throw.
        #expect(JavaOptions.parse("-Dname=\"two words") == ["-Dname=two words"])
    }

    @Test func keepsOrder() {
        #expect(JavaOptions.parse("-a -b -c") == ["-a", "-b", "-c"])
    }

    @Test func passesThroughOptionsWeWouldNeverRecommend() {
        // Nothing is filtered on purpose.
        #expect(JavaOptions.parse("-jar other.jar") == ["-jar", "other.jar"])
    }
}
