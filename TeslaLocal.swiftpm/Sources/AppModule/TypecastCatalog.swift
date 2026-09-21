//
//  TypecastCatalog.swift
//  YLCompanion
//
//  Typecast AI Korean Female Young Adult Catalog (131 Characters)
//
import Foundation

public struct TypecastCharacter: Identifiable, Hashable {
    public let id: String        // actor_id
    public let nameKo: String
    public let nameEn: String
    public let tone: String
    public let mood: String
    public let category: String
    public let desc: String

    public var isCuratedPreset: Bool {
        ["은경", "서현", "아엘", "한영"].contains(nameKo)
    }
}

public enum TypecastCatalog {
    public static let characters: [TypecastCharacter] = [
        TypecastCharacter(
            id: "6a7446c19f2d7dfed990a900",
            nameKo: "은경",
            nameEn: "Eunkyung",
            tone: "중음",
            mood: "차분한, 따뜻한",
            category: "Conversational, Radio/Podcast",
            desc: "차분한, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "69f2e455ea79fd197aa0476f",
            nameKo: "서현",
            nameEn: "Seohyeon",
            tone: "중음",
            mood: "신뢰감있는, 차분한",
            category: "Announcer, Conversational",
            desc: "신뢰감있는, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "676cda78bde49be9d17f38e0",
            nameKo: "아엘",
            nameEn: "Ael",
            tone: "중고음",
            mood: "신뢰감있는, 세련된",
            category: "Game",
            desc: "신뢰감있는, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6731b3ac075b04a944644234",
            nameKo: "한영",
            nameEn: "Hanyoung",
            tone: "중저음",
            mood: "차분한, 신뢰감있는",
            category: "Radio/Podcast, Audiobook/Storytelling",
            desc: "차분한, 신뢰감있는 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "631725778f5340201e988f95",
            nameKo: "MBTI EF 여",
            nameEn: "MBTI EF (F)",
            tone: "중고음",
            mood: "힘 있는, 밝은",
            category: "Conversational",
            desc: "힘 있는, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "631725654e0d806f7158efd1",
            nameKo: "MBTI ET 여",
            nameEn: "MBTI ET (F)",
            tone: "중음",
            mood: "힘 있는, 신뢰감있는",
            category: "Conversational",
            desc: "힘 있는, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "630ddaf7d139b3219b28dd48",
            nameKo: "MBTI IF 여",
            nameEn: "MBTI IF (F)",
            tone: "고음",
            mood: "차분한, 따뜻한",
            category: "Conversational",
            desc: "차분한, 따뜻한 · 고음 톤"
        ),
        TypecastCharacter(
            id: "630ddae602e347147b7d95b0",
            nameKo: "MBTI IT 여",
            nameEn: "MBTI IT (F)",
            tone: "중저음",
            mood: "차가운, 차분한",
            category: "Conversational",
            desc: "차가운, 차분한 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "66d021f10742c43c93a0d629",
            nameKo: "MC미자",
            nameEn: "MC MIJA",
            tone: "고음",
            mood: "신뢰감있는, 밝은, 힘 있는",
            category: "E-learning/Explainer",
            desc: "신뢰감있는, 밝은, 힘 있는 · 고음 톤"
        ),
        TypecastCharacter(
            id: "60f7a217279ffba711ce2958",
            nameKo: "가을",
            nameEn: "Gaeul",
            tone: "중고음",
            mood: "힘 있는, 감성적인",
            category: "Audiobook/Storytelling",
            desc: "힘 있는, 감성적인 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "624ccc04adcd568510764d3f",
            nameKo: "가희",
            nameEn: "Gahee",
            tone: "중음",
            mood: "차가운, 감성적인",
            category: "Conversational, Ads/Promotion, Game, TikTok/Reels/Shorts",
            desc: "차가운, 감성적인 · 중음 톤"
        ),
        TypecastCharacter(
            id: "5e4f7a5da82e1f000aca31af",
            nameKo: "강수정 기자",
            nameEn: "Reporter Kang",
            tone: "중음",
            mood: "신뢰감있는, 힘 있는",
            category: "Announcer",
            desc: "신뢰감있는, 힘 있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "62849ce44b8771d984838066",
            nameKo: "강수정 캐스터",
            nameEn: "Sportscaster Kang",
            tone: "중고음",
            mood: "밝은, 따뜻한",
            category: "News Reporter",
            desc: "밝은, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "620c51951c4454a25c855aab",
            nameKo: "강초연 교관",
            nameEn: "Choyeon",
            tone: "중음",
            mood: "힘 있는, 신뢰감있는",
            category: "Ads/Promotion",
            desc: "힘 있는, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "606c6b127b9f53b4cd1743f5",
            nameKo: "개나리",
            nameEn: "Nari",
            tone: "고음",
            mood: "밝은, 귀여운, 기타",
            category: "Conversational",
            desc: "밝은, 귀여운, 기타 · 고음 톤"
        ),
        TypecastCharacter(
            id: "65c35b4c3940821a381243fd",
            nameKo: "겜스터",
            nameEn: "Gamester",
            tone: "중음",
            mood: "차가운",
            category: "",
            desc: "차가운 · 중음 톤"
        ),
        TypecastCharacter(
            id: "68785db8ba9cd7503f27d921",
            nameKo: "고운",
            nameEn: "Gowoon",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "Conversational, Radio/Podcast",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "659684d457333e980515bc6d",
            nameKo: "꼬미",
            nameEn: "Ggomi",
            tone: "고음",
            mood: "밝은, 가벼운",
            category: "E-learning/Explainer",
            desc: "밝은, 가벼운 · 고음 톤"
        ),
        TypecastCharacter(
            id: "66d01e8645a4605d68e258eb",
            nameKo: "나교육",
            nameEn: "NAGYOYUK",
            tone: "중음",
            mood: "신뢰감있는, 차분한, 밝은",
            category: "E-learning/Explainer",
            desc: "신뢰감있는, 차분한, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6aab6f4f07622ec83b7ec21a",
            nameKo: "나윤",
            nameEn: "Nayoon",
            tone: "중고음",
            mood: "차분한, 귀여운",
            category: "Radio/Podcast, Conversational",
            desc: "차분한, 귀여운 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "662a05cf14d4a303e5d0baa2",
            nameKo: "나은",
            nameEn: "Naeun",
            tone: "중음",
            mood: "차분한, 세련된",
            category: "Conversational",
            desc: "차분한, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6335061c3c90cf9e5b6b9fff",
            nameKo: "다나",
            nameEn: "Dana",
            tone: "중저음",
            mood: "따뜻한, 밝은",
            category: "TikTok/Reels/Shorts",
            desc: "따뜻한, 밝은 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "5fd89baaf8864c404f9097f4",
            nameKo: "다보나 기자",
            nameEn: "Reporter Bona",
            tone: "중저음",
            mood: "신뢰감있는, 힘 있는",
            category: "News Reporter",
            desc: "신뢰감있는, 힘 있는 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "692799c46508f6b9468c54c7",
            nameKo: "다은",
            nameEn: "Daeun",
            tone: "중고음",
            mood: "귀여운, 밝은",
            category: "TikTok/Reels/Shorts, Conversational",
            desc: "귀여운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "646f0dac2465b38f37787f64",
            nameKo: "다현",
            nameEn: "Dahyeon",
            tone: "중음",
            mood: "차가운, 차분한",
            category: "TikTok/Reels/Shorts",
            desc: "차가운, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "60bf72699042ef1da40214c7",
            nameKo: "데이지",
            nameEn: "DVZY",
            tone: "중저음",
            mood: "힘 있는, 세련된, 기타",
            category: "Rapper",
            desc: "힘 있는, 세련된, 기타 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "61f084d860b9b6b40388f868",
            nameKo: "라라",
            nameEn: "Lala",
            tone: "중고음",
            mood: "따뜻한, 힘 있는",
            category: "TikTok/Reels/Shorts",
            desc: "따뜻한, 힘 있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "60194446adfd1fbe5e0dd975",
            nameKo: "라미",
            nameEn: "Lamie",
            tone: "고음",
            mood: "밝은, 귀여운",
            category: "Ads/Promotion",
            desc: "밝은, 귀여운 · 고음 톤"
        ),
        TypecastCharacter(
            id: "68413e12459cfdf27b481183",
            nameKo: "라연",
            nameEn: "Rayeon",
            tone: "중저음",
            mood: "따뜻한, 차분한",
            category: "Conversational, Radio/Podcast",
            desc: "따뜻한, 차분한 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "66d01e69a0b11cba718e9058",
            nameKo: "라일라",
            nameEn: "Layla",
            tone: "중음",
            mood: "차가운, 세련된",
            category: "Documentary",
            desc: "차가운, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "61377f7ca4d286537b5aba6c",
            nameKo: "로미",
            nameEn: "Romi",
            tone: "중고음",
            mood: "귀여운, 차가운",
            category: "Voicemail/Voice Assistant",
            desc: "귀여운, 차가운 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "609b98c2e587f6dbd19414b9",
            nameKo: "루나",
            nameEn: "Luna",
            tone: "고음",
            mood: "밝은, 따뜻한",
            category: "Radio/Podcast, Game",
            desc: "밝은, 따뜻한 · 고음 톤"
        ),
        TypecastCharacter(
            id: "66d01e3845a4605d68e2588a",
            nameKo: "루미나",
            nameEn: "Lumina",
            tone: "중음",
            mood: "밝은, 감성적인, 따뜻한, 가벼운",
            category: "Audiobook/Storytelling",
            desc: "밝은, 감성적인, 따뜻한, 가벼운 · 중음 톤"
        ),
        TypecastCharacter(
            id: "68257b1c05d24e70414c96e6",
            nameKo: "무영",
            nameEn: "Muyoung",
            tone: "저음",
            mood: "신뢰감있는, 차분한, 세련된, 힘 있는",
            category: "Documentary",
            desc: "신뢰감있는, 차분한, 세련된, 힘 있는 · 저음 톤"
        ),
        TypecastCharacter(
            id: "68f9c6a72f0f04a417bb136f",
            nameKo: "문정",
            nameEn: "Moonjung",
            tone: "중음",
            mood: "차분한, 따뜻한",
            category: "E-learning/Explainer, Conversational",
            desc: "차분한, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6620d242904c5eef906092eb",
            nameKo: "미리내",
            nameEn: "Mirine",
            tone: "중음",
            mood: "힘 있는, 신뢰감있는",
            category: "News Reporter, TikTok/Reels/Shorts",
            desc: "힘 있는, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "63745dd5e0b6db6f3cf10924",
            nameKo: "미진",
            nameEn: "Mijin",
            tone: "중고음",
            mood: "차분한, 신뢰감있는",
            category: "E-learning/Explainer",
            desc: "차분한, 신뢰감있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6699eb0f10b8e361d6a9aba1",
            nameKo: "민정",
            nameEn: "Minjung",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "Audiobook/Storytelling",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6731b36bd944a485bc4070fd",
            nameKo: "민주",
            nameEn: "Minju",
            tone: "고음",
            mood: "가벼운, 가벼운",
            category: "Conversational, TikTok/Reels/Shorts",
            desc: "가벼운, 가벼운 · 고음 톤"
        ),
        TypecastCharacter(
            id: "5eb55ce920d1b60016e91de6",
            nameKo: "민지",
            nameEn: "Minji",
            tone: "중고음",
            mood: "따뜻한, 힘 있는",
            category: "Documentary, Audiobook/Storytelling",
            desc: "따뜻한, 힘 있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "66b4523f259dc43de649c1d1",
            nameKo: "민채",
            nameEn: "Minchae",
            tone: "중고음",
            mood: "밝은, 신뢰감있는",
            category: "Documentary",
            desc: "밝은, 신뢰감있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "682e7a1a7608634e98387a1b",
            nameKo: "민희",
            nameEn: "Minhee",
            tone: "고음",
            mood: "귀여운, 가벼운, 밝은, 힘 있는",
            category: "Podcast",
            desc: "귀여운, 가벼운, 밝은, 힘 있는 · 고음 톤"
        ),
        TypecastCharacter(
            id: "60478557f12456064b353409",
            nameKo: "발키리",
            nameEn: "Valkyrie",
            tone: "중고음",
            mood: "힘 있는, 감성적인",
            category: "TikTok/Reels/Shorts",
            desc: "힘 있는, 감성적인 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "618203f635ea62f8574c7d8a",
            nameKo: "보라",
            nameEn: "Bora",
            tone: "중고음",
            mood: "귀여운, 밝은",
            category: "Game",
            desc: "귀여운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "623a76ac9f23b33782186c03",
            nameKo: "새미",
            nameEn: "Sammy",
            tone: "중음",
            mood: "힘 있는, 밝은",
            category: "TikTok/Reels/Shorts",
            desc: "힘 있는, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "637cbfeef7f00f21e8a1c6c8",
            nameKo: "서연",
            nameEn: "Seoyeon",
            tone: "중고음",
            mood: "힘 있는, 따뜻한",
            category: "E-learning/Explainer",
            desc: "힘 있는, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "68537c9420b646f2176890ba",
            nameKo: "서진",
            nameEn: "Seojin",
            tone: "중고음",
            mood: "따뜻한, 밝은",
            category: "Conversational, Radio/Podcast",
            desc: "따뜻한, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "66d91cac31a58a718f750a49",
            nameKo: "서희",
            nameEn: "Seohee",
            tone: "중저음",
            mood: "기타, 따뜻한",
            category: "Conversational",
            desc: "기타, 따뜻한 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "649408f268febb61286eec85",
            nameKo: "선하",
            nameEn: "Seonha",
            tone: "중저음",
            mood: "따뜻한, 차분한",
            category: "E-learning/Explainer",
            desc: "따뜻한, 차분한 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "6731b307df12333201d12b94",
            nameKo: "설화",
            nameEn: "Seolhwa",
            tone: "중고음",
            mood: "세련된, 차분한",
            category: "Conversational, Documentary",
            desc: "세련된, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "622964d6255364be41659078",
            nameKo: "세나",
            nameEn: "Sena",
            tone: "중음",
            mood: "밝은, 따뜻한",
            category: "Conversational",
            desc: "밝은, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "611c3f692fac944dff493a04",
            nameKo: "세희",
            nameEn: "SeHee",
            tone: "중고음",
            mood: "차분한, 따뜻한",
            category: "Documentary",
            desc: "차분한, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "62c3de188bb43a2b3ab3ef08",
            nameKo: "소라",
            nameEn: "Sora",
            tone: "중고음",
            mood: "가벼운, 기타",
            category: "Conversational",
            desc: "가벼운, 기타 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6837dec48fc46637a9272b88",
            nameKo: "소예",
            nameEn: "Soye",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "Conversational, Radio/Podcast",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "62b17f026fe31dc29ac8e94e",
            nameKo: "소율",
            nameEn: "Soyul",
            tone: "중음",
            mood: "밝은, 밝은",
            category: "TikTok/Reels/Shorts",
            desc: "밝은, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "666a9871abcf27a5169850d0",
            nameKo: "소진",
            nameEn: "Sojin",
            tone: "중고음",
            mood: "귀여운, 밝은",
            category: "Audiobook/Storytelling, Radio/Podcast, Ads/Promotion",
            desc: "귀여운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "642f9d147ce3f79717423466",
            nameKo: "소혜",
            nameEn: "Sohye",
            tone: "중음",
            mood: "신뢰감있는, 세련된",
            category: "E-learning/Explainer",
            desc: "신뢰감있는, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6050baed630c0d0906e65cc5",
            nameKo: "쇼린이",
            nameEn: "E-seller Sherri",
            tone: "고음",
            mood: "밝은, 따뜻한",
            category: "Ads/Promotion, TikTok/Reels/Shorts",
            desc: "밝은, 따뜻한 · 고음 톤"
        ),
        TypecastCharacter(
            id: "66e266f9c568136dce8164e5",
            nameKo: "수민",
            nameEn: "Sumin",
            tone: "중음",
            mood: "밝은, 신뢰감있는",
            category: "Documentary",
            desc: "밝은, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "63aaec0d34ca719d00798a97",
            nameKo: "수빈",
            nameEn: "Soobin",
            tone: "중음",
            mood: "힘 있는, 따뜻한",
            category: "Conversational",
            desc: "힘 있는, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6763bef751dc3fb17792acaf",
            nameKo: "수윤",
            nameEn: "Suyoon",
            tone: "중고음",
            mood: "밝은, 힘 있는",
            category: "Documentary",
            desc: "밝은, 힘 있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "62686cc30e70d8c6b0d9b010",
            nameKo: "수지",
            nameEn: "Suji",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "Radio/Podcast",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "5c3c52ca5827e00008dd7f3a",
            nameKo: "수진",
            nameEn: "Sujin",
            tone: "중고음",
            mood: "차분한, 밝은",
            category: "E-learning/Explainer",
            desc: "차분한, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6453435e7a050a4142d4997e",
            nameKo: "승아",
            nameEn: "Seungah",
            tone: "중음",
            mood: "밝은, 신뢰감있는",
            category: "Radio/Podcast",
            desc: "밝은, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "63622aa127f06f51e93a873c",
            nameKo: "승연",
            nameEn: "Seungyeon",
            tone: "중음",
            mood: "세련된, 차분한",
            category: "E-learning/Explainer",
            desc: "세련된, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6568164fe05ddffee8b0e271",
            nameKo: "시연",
            nameEn: "Siyeon",
            tone: "중저음",
            mood: "밝은, 신뢰감있는",
            category: "Radio/Podcast",
            desc: "밝은, 신뢰감있는 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "5ecbbc4b0fbab10007bb3c7d",
            nameKo: "신혜",
            nameEn: "Shinhe",
            tone: "중음",
            mood: "차분한",
            category: "Documentary",
            desc: "차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "64004d04ef92a9a77bd86ca1",
            nameKo: "아랑",
            nameEn: "Arang",
            tone: "중음",
            mood: "따뜻한, 밝은",
            category: "Conversational, Radio/Podcast",
            desc: "따뜻한, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6047863af12456064b35354e",
            nameKo: "아리",
            nameEn: "Ari",
            tone: "중고음",
            mood: "차분한, 밝은",
            category: "Conversational",
            desc: "차분한, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "67513c3cf30802da48949a14",
            nameKo: "아린",
            nameEn: "Arin",
            tone: "중고음",
            mood: "밝은, 따뜻한",
            category: "Ads/Promotion",
            desc: "밝은, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "63eb40c91a29b27ab08f2123",
            nameKo: "에밀리(Ko)",
            nameEn: "Emily(Ko)",
            tone: "중고음",
            mood: "차분한, 세련된",
            category: "",
            desc: "차분한, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "64b0eede22ce103fdc1d9f78",
            nameKo: "연서",
            nameEn: "Yeonsuh",
            tone: "중저음",
            mood: "힘 있는, 세련된",
            category: "Documentary, Radio/Podcast",
            desc: "힘 있는, 세련된 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "63e4665f44a08572e32da6e9",
            nameKo: "연아",
            nameEn: "Yeonah",
            tone: "중고음",
            mood: "차분한, 따뜻한",
            category: "TikTok/Reels/Shorts",
            desc: "차분한, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "5c3c52caea9791000747155e",
            nameKo: "영희",
            nameEn: "Younghee",
            tone: "고음",
            mood: "세련된, 따뜻한",
            category: "Voicemail/Voice Assistant",
            desc: "세련된, 따뜻한 · 고음 톤"
        ),
        TypecastCharacter(
            id: "61e748d0fd9fb2d2cacbb04d",
            nameKo: "예나",
            nameEn: "Yena",
            tone: "중고음",
            mood: "밝은, 따뜻한",
            category: "Conversational",
            desc: "밝은, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "611c406d9540d10d3002e03a",
            nameKo: "예린",
            nameEn: "YeLin",
            tone: "중고음",
            mood: "밝은, 따뜻한",
            category: "Radio/Podcast",
            desc: "밝은, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "66ab0e26ec23f325b7ad51df",
            nameKo: "예슬",
            nameEn: "Yeseul",
            tone: "중저음",
            mood: "차분한, 힘 있는",
            category: "Radio/Podcast",
            desc: "차분한, 힘 있는 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "65f280c8bca6a9dc5c12c348",
            nameKo: "예은",
            nameEn: "Yeeun",
            tone: "중고음",
            mood: "세련된, 기타",
            category: "TikTok/Reels/Shorts",
            desc: "세련된, 기타 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "67c90ad544cf859417f2fc3a",
            nameKo: "예진",
            nameEn: "Yejin",
            tone: "중저음",
            mood: "밝은, 감성적인",
            category: "Conversational",
            desc: "밝은, 감성적인 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "675a74035ff33c1eeff6255f",
            nameKo: "원경",
            nameEn: "Wonkyung",
            tone: "중저음",
            mood: "차가운, 차가운",
            category: "TikTok/Reels/Shorts",
            desc: "차가운, 차가운 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "610cf768cd5a65c12893dab7",
            nameKo: "유나(Ko)",
            nameEn: "Yuna (Ko)",
            tone: "중음",
            mood: "신뢰감있는, 힘 있는",
            category: "",
            desc: "신뢰감있는, 힘 있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "61130d6cf89dd58a4c13295d",
            nameKo: "유라",
            nameEn: "Yura",
            tone: "중고음",
            mood: "밝은, 세련된",
            category: "Documentary, Ads/Promotion, Audiobook/Storytelling, Radio/Podcast",
            desc: "밝은, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "65e96ab52564d1136ecb1d67",
            nameKo: "유미",
            nameEn: "Yumi",
            tone: "중음",
            mood: "차가운, 차가운",
            category: "Conversational",
            desc: "차가운, 차가운 · 중음 톤"
        ),
        TypecastCharacter(
            id: "648187771b32756f613acec3",
            nameKo: "유민",
            nameEn: "Yumin",
            tone: "중음",
            mood: "힘 있는, 세련된",
            category: "Audiobook/Storytelling",
            desc: "힘 있는, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "64818789444a9ae3e2e9f89d",
            nameKo: "유빈",
            nameEn: "Yubin",
            tone: "중고음",
            mood: "세련된, 힘 있는",
            category: "Audiobook/Storytelling, Radio/Podcast, Ads/Promotion",
            desc: "세련된, 힘 있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "64818767272f62f8ddb73948",
            nameKo: "유진",
            nameEn: "Yujin",
            tone: "중고음",
            mood: "신뢰감있는, 차분한",
            category: "Audiobook/Storytelling",
            desc: "신뢰감있는, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "681059782dc4759327e3d302",
            nameKo: "유하",
            nameEn: "Yuha",
            tone: "중음",
            mood: "가벼운, 귀여운, 밝은",
            category: "Audiobook",
            desc: "가벼운, 귀여운, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "66d91c60da8dd20be59cd40b",
            nameKo: "윤서",
            nameEn: "Yoonseo",
            tone: "중고음",
            mood: "기타, 밝은",
            category: "Conversational",
            desc: "기타, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "660e45ff50e0ecacaf967d22",
            nameKo: "은빈",
            nameEn: "Eunbin",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "Ads/Promotion",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "67db72eb93add6902ea41e5c",
            nameKo: "은솔",
            nameEn: "Eunsol",
            tone: "중음",
            mood: "신뢰감있는, 밝은",
            category: "Voicemail/Voice Assistant",
            desc: "신뢰감있는, 밝은 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6398408eb30b5ad2cfd29542",
            nameKo: "은아",
            nameEn: "Eunah",
            tone: "중고음",
            mood: "신뢰감있는, 세련된",
            category: "",
            desc: "신뢰감있는, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "663343c5b1f85ebd9f4896b9",
            nameKo: "은채",
            nameEn: "Eunchae",
            tone: "중고음",
            mood: "세련된, 힘 있는",
            category: "E-learning/Explainer, News Reporter, TikTok/Reels/Shorts",
            desc: "세련된, 힘 있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "65cd94c242e2d9d9c9c905e7",
            nameKo: "은하",
            nameEn: "Eunha",
            tone: "중고음",
            mood: "세련된, 기타",
            category: "TikTok/Reels/Shorts",
            desc: "세련된, 기타 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "62686be9deec4c1bb7fd077c",
            nameKo: "이나",
            nameEn: "Ina",
            tone: "중저음",
            mood: "따뜻한, 힘 있는",
            category: "TikTok/Reels/Shorts",
            desc: "따뜻한, 힘 있는 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "60915b5616d74069af8e8cab",
            nameKo: "이보미",
            nameEn: "Bomi",
            tone: "중고음",
            mood: "차분한, 신뢰감있는",
            category: "Voicemail/Voice Assistant",
            desc: "차분한, 신뢰감있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "68ddea1e462b169ddd20b74d",
            nameKo: "이현",
            nameEn: "Leehyun",
            tone: "중고음",
            mood: "따뜻한, 차분한",
            category: "E-learning/Explainer, Conversational",
            desc: "따뜻한, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "66c6ce360614b40f9fe13439",
            nameKo: "인혜",
            nameEn: "Inhye",
            tone: "중음",
            mood: "세련된, 따뜻한",
            category: "Documentary",
            desc: "세련된, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "612ed01c7eb720fddd3ddedf",
            nameKo: "재이",
            nameEn: "JaeYi",
            tone: "중고음",
            mood: "차분한, 가벼운",
            category: "Conversational",
            desc: "차분한, 가벼운 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "641c10c956c8ba415e6a1101",
            nameKo: "정아",
            nameEn: "Jeongah",
            tone: "중음",
            mood: "차분한, 신뢰감있는",
            category: "Radio/Podcast",
            desc: "차분한, 신뢰감있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "5ebea1a364afaf00087fc2fb",
            nameKo: "정희",
            nameEn: "Junghee",
            tone: "중음",
            mood: "세련된, 차분한",
            category: "E-learning/Explainer",
            desc: "세련된, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "66f4ecb5b1a24ceec9f6ccf0",
            nameKo: "주영",
            nameEn: "Juyoung",
            tone: "중저음",
            mood: "따뜻한, 차분한",
            category: "Radio/Podcast",
            desc: "따뜻한, 차분한 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "63b6650cd4db9f9f9bc4ad84",
            nameKo: "주은",
            nameEn: "Jooeun",
            tone: "중고음",
            mood: "따뜻한, 세련된",
            category: "News Reporter",
            desc: "따뜻한, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "5ebea194728f5b00075e61e8",
            nameKo: "쥬비",
            nameEn: "Jewby",
            tone: "중고음",
            mood: "밝은, 세련된",
            category: "Ads/Promotion",
            desc: "밝은, 세련된 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "5c789c34dabcfa0008b0a390",
            nameKo: "지영",
            nameEn: "Jiyoung",
            tone: "중음",
            mood: "밝은, 따뜻한",
            category: "Documentary",
            desc: "밝은, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "62296627a4ff5d1ee6bf4ecc",
            nameKo: "지윤",
            nameEn: "Jiyoon",
            tone: "중고음",
            mood: "차분한, 신뢰감있는",
            category: "Documentary",
            desc: "차분한, 신뢰감있는 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "65f280ecf1a9fb325938fdf9",
            nameKo: "지현",
            nameEn: "Jihyun",
            tone: "중고음",
            mood: "감성적인, 차분한",
            category: "TikTok/Reels/Shorts",
            desc: "감성적인, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "60a3c91b4bc87f0d62b09a50",
            nameKo: "지희",
            nameEn: "Jihee",
            tone: "중고음",
            mood: "차분한, 따뜻한",
            category: "Voicemail/Voice Assistant",
            desc: "차분한, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "65bb3a1976b69213594357fc",
            nameKo: "진서",
            nameEn: "Jinseo",
            tone: "중고음",
            mood: "따뜻한, 차분한",
            category: "Ads/Promotion, TikTok/Reels/Shorts, Documentary, Audiobook/Storytelling, Radio/Podcast",
            desc: "따뜻한, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6731b2b2478a48710ecc9158",
            nameKo: "진희",
            nameEn: "Jinhee",
            tone: "중음",
            mood: "신뢰감있는, 차분한",
            category: "Announcer, News Reporter",
            desc: "신뢰감있는, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "67513c5a498d6471f99d48fc",
            nameKo: "청아",
            nameEn: "Chungah",
            tone: "중음",
            mood: "힘 있는, 힘 있는",
            category: "TikTok/Reels/Shorts",
            desc: "힘 있는, 힘 있는 · 중음 톤"
        ),
        TypecastCharacter(
            id: "65e02cf60c83f6b4209f4343",
            nameKo: "최미란",
            nameEn: "Miran Choi",
            tone: "중고음",
            mood: "세련된, 기타",
            category: "Audiobook/Storytelling, Announcer, Voicemail/Voice Assistant",
            desc: "세련된, 기타 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "63e4665444a08572e32da6e1",
            nameKo: "최정",
            nameEn: "Jeong Choi",
            tone: "중저음",
            mood: "귀여운, 밝은",
            category: "TikTok/Reels/Shorts",
            desc: "귀여운, 밝은 · 중저음 톤"
        ),
        TypecastCharacter(
            id: "68105948c9bee82695791e79",
            nameKo: "투룰툴툴",
            nameEn: "Turultultul",
            tone: "고음",
            mood: "감성적인, 차가운, 기타, 힘 있는",
            category: "Ads",
            desc: "감성적인, 차가운, 기타, 힘 있는 · 고음 톤"
        ),
        TypecastCharacter(
            id: "61659cc118732016a95fe7c6",
            nameKo: "하나",
            nameEn: "Hana",
            tone: "중고음",
            mood: "기타, 차가운",
            category: "TikTok/Reels/Shorts",
            desc: "기타, 차가운 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "606324cd7b4da19a1f6100be",
            nameKo: "하늘 캐스터",
            nameEn: "Weather Reporter Sky",
            tone: "고음",
            mood: "밝은, 따뜻한",
            category: "News Reporter",
            desc: "밝은, 따뜻한 · 고음 톤"
        ),
        TypecastCharacter(
            id: "61de28df641213266e24a831",
            nameKo: "하라",
            nameEn: "Hara",
            tone: "저음",
            mood: "신뢰감있는, 세련된",
            category: "",
            desc: "신뢰감있는, 세련된 · 저음 톤"
        ),
        TypecastCharacter(
            id: "6271b9b22b3bf7947c23e9bc",
            nameKo: "하린",
            nameEn: "Harin",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "TikTok/Reels/Shorts",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "66d01ed3b5e6dcf72d9e3ad7",
            nameKo: "한그리",
            nameEn: "Hangeri",
            tone: "중음",
            mood: "기타, 밝은, 가벼운, 차분한",
            category: "Radio/Podcast",
            desc: "기타, 밝은, 가벼운, 차분한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "628d9e0e1374f7682602991b",
            nameKo: "한나",
            nameEn: "Hanna",
            tone: "",
            mood: "차분한, 힘 있는",
            category: "Audiobook/Storytelling",
            desc: "차분한, 힘 있는"
        ),
        TypecastCharacter(
            id: "66d01e4ebda076835c38dc65",
            nameKo: "한서린",
            nameEn: "Scary girl",
            tone: "중음",
            mood: "차분한, 차가운",
            category: "Documentary",
            desc: "차분한, 차가운 · 중음 톤"
        ),
        TypecastCharacter(
            id: "661797923ed12f31b61c4b5f",
            nameKo: "한솔",
            nameEn: "Hansol",
            tone: "중고음",
            mood: "귀여운, 밝은",
            category: "Audiobook/Storytelling",
            desc: "귀여운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6788847e9939d48aeb8642d2",
            nameKo: "해랑",
            nameEn: "Haerang",
            tone: "중고음",
            mood: "따뜻한, 따뜻한",
            category: "Conversational",
            desc: "따뜻한, 따뜻한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "632293ed2f894f2211e8c597",
            nameKo: "햄쮸",
            nameEn: "Hamchu",
            tone: "중고음",
            mood: "귀여운, 밝은",
            category: "Anime",
            desc: "귀여운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "6335062fd260d463f7d7abb9",
            nameKo: "현주",
            nameEn: "Hyunju",
            tone: "중음",
            mood: "차분한, 세련된",
            category: "Documentary",
            desc: "차분한, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "66d00104bda076835c38ba68",
            nameKo: "현지",
            nameEn: "Hyunji",
            tone: "중고음",
            mood: "차분한, 차분한",
            category: "TikTok/Reels/Shorts",
            desc: "차분한, 차분한 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "5d01a522bb04140008a23f34",
            nameKo: "현진",
            nameEn: "Hyunjin",
            tone: "중음",
            mood: "신뢰감있는, 세련된",
            category: "Voicemail/Voice Assistant",
            desc: "신뢰감있는, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "65d6f8ee2b58da07b6284a56",
            nameKo: "혜나",
            nameEn: "Hyena",
            tone: "중고음",
            mood: "가벼운, 밝은",
            category: "Ads/Promotion",
            desc: "가벼운, 밝은 · 중고음 톤"
        ),
        TypecastCharacter(
            id: "62e8f21e979b3860fe2f6a24",
            nameKo: "혜리",
            nameEn: "Hyelee",
            tone: "중음",
            mood: "밝은, 따뜻한",
            category: "TikTok/Reels/Shorts, Ads/Promotion",
            desc: "밝은, 따뜻한 · 중음 톤"
        ),
        TypecastCharacter(
            id: "667ce80314cb3a612d6959e8",
            nameKo: "혜민",
            nameEn: "Hyemin",
            tone: "중음",
            mood: "세련된, 차가운",
            category: "TikTok/Reels/Shorts",
            desc: "세련된, 차가운 · 중음 톤"
        ),
        TypecastCharacter(
            id: "691d49ccc47926d741f15913",
            nameKo: "효은",
            nameEn: "Hyoeun",
            tone: "중음",
            mood: "따뜻한, 세련된",
            category: "E-learning/Explainer, Radio/Podcast",
            desc: "따뜻한, 세련된 · 중음 톤"
        ),
        TypecastCharacter(
            id: "6229d5f8e7a9e96c2f6f3932",
            nameKo: "희연",
            nameEn: "Heeyeon",
            tone: "중음",
            mood: "따뜻한, 차분한",
            category: "",
            desc: "따뜻한, 차분한 · 중음 톤"
        ),
    ]

    private static let byId: [String: TypecastCharacter] = {
        var dict: [String: TypecastCharacter] = [:]
        for char in characters {
            dict[char.id.lowercased()] = char
        }
        return dict
    }()

    private static let byNameKo: [String: TypecastCharacter] = {
        var dict: [String: TypecastCharacter] = [:]
        for char in characters {
            dict[char.nameKo.lowercased()] = char
        }
        return dict
    }()

    private static let byNameEn: [String: TypecastCharacter] = {
        var dict: [String: TypecastCharacter] = [:]
        for char in characters {
            dict[char.nameEn.lowercased()] = char
        }
        return dict
    }()

    public static func find(_ query: String) -> TypecastCharacter? {
        let clean = query.replacingOccurrences(of: "typecast:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }

        if let direct = byId[clean] { return direct }
        if let directKo = byNameKo[clean] { return directKo }
        if let directEn = byNameEn[clean] { return directEn }

        // Match without spaces
        let noSpaces = clean.replacingOccurrences(of: " ", with: "")
        if let match = characters.first(where: {
            $0.nameKo.replacingOccurrences(of: " ", with: "").lowercased() == noSpaces ||
            $0.nameEn.replacingOccurrences(of: " ", with: "").lowercased() == noSpaces ||
            $0.id.lowercased().contains(noSpaces)
        }) {
            return match
        }

        // Substring match
        return characters.first(where: {
            $0.nameKo.lowercased().contains(clean) || clean.contains($0.nameKo.lowercased())
        })
    }

    public static func search(query: String, category: String = "전체") -> [TypecastCharacter] {
        var results = characters
        if category != "전체" {
            results = results.filter { char in
                switch category {
                case "대화/일상":
                    return char.category.localizedCaseInsensitiveContains("Conversational") || char.desc.contains("대화")
                case "아나운서/기자":
                    return char.category.localizedCaseInsensitiveContains("Announcer") || char.desc.contains("아나운서") || char.desc.contains("기자")
                case "오디오북/낭독":
                    return char.category.localizedCaseInsensitiveContains("Audiobook") || char.category.localizedCaseInsensitiveContains("Storytelling") || char.desc.contains("낭독")
                case "라디오/팟캐스트":
                    return char.category.localizedCaseInsensitiveContains("Radio") || char.category.localizedCaseInsensitiveContains("Podcast") || char.desc.contains("라디오")
                case "광고/홍보":
                    return char.category.localizedCaseInsensitiveContains("Ad") || char.category.localizedCaseInsensitiveContains("Promo") || char.desc.contains("광고")
                default:
                    return true
                }
            }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return results }
        return results.filter {
            $0.nameKo.lowercased().contains(q) ||
            $0.nameEn.lowercased().contains(q) ||
            $0.mood.lowercased().contains(q) ||
            $0.tone.lowercased().contains(q) ||
            $0.desc.lowercased().contains(q)
        }
    }
}