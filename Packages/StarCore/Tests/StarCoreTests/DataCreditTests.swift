import Foundation
import Testing
@testable import StarCore

@Suite struct DataCreditTests {
    @Test func idsAreUnique() {
        let ids = DataCredit.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// 出典の表示が利用の条件になっているものは、一覧から落とさない
    @Test func requiredCreditsAreListed() {
        let ids = Set(DataCredit.all.map(\.id))
        for id in ["plateau", "gsi-tiles", "viirs", "open-meteo", "nasa-starmap", "gaia", "d3-celestial", "nasa-moon"] {
            #expect(ids.contains(id), "\(id) が出典の一覧に無い")
        }
    }

    @Test func linksUseHTTPS() {
        for credit in DataCredit.all {
            if let url = credit.url { #expect(url.scheme == "https", "\(credit.id)") }
        }
    }

    @Test func unknownLicenseIsShownAsUnconfirmed() {
        let gaia = DataCredit.all.first { $0.id == "gaia" }
        #expect(gaia?.licenseText == "利用条件を確認中")
        #expect(DataCredit.all.first { $0.id == "open-meteo" }?.licenseText == "CC BY 4.0")
    }
}
